// Copyright (C) 2026 Kizuna contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#define NOMINMAX
#include <Windows.h>

#include <io.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include "CrnnNet.h"
#include "DbNet.h"
#include "OcrUtils.h"

namespace {

constexpr int kProtocolVersion = 1;
constexpr int kMaxRegions = 512;

// Fixed for this port, matching what the Paddle worker asks PaddleOCR for
// today. Issue #14 turns them into command-line options; until then a payload
// cannot be swept without rebuilding, which is the same position the Paddle
// worker started from.
constexpr int kDetectionSideLength = 960;
constexpr float kBoxScoreThreshold = 0.6f;
constexpr float kBoxThreshold = 0.3f;
constexpr float kUnclipRatio = 1.5f;
// One [N,3,48,320] Run rather than upstream's one-Run-per-region loop; see
// ppocr/patches/0002. Measured at 90 -> 80 ms p50 on the fixture.
constexpr int kRecognitionBatchSize = 8;
constexpr int kRecognitionWidth = 320;

// The recogniser has 18385 output classes: index 0 is the CTC blank, 1..18383
// the dictionary, and 18384 a space. CrnnNet supplies the blank and the space
// itself, so a dictionary of any other length shifts every index and decodes to
// plausible-looking garbage instead of failing. Checking the count here is what
// turns that into a startup error.
constexpr size_t kDictionaryEntries = 18383;

// Recognition crops taller than they are wide are rotated by the engine, and a
// crop with no area cannot be warped at all; both are dropped rather than left
// to raise an OpenCV error that would fail the whole capture.
constexpr int kMinimumCropSide = 1;

// ---------------------------------------------------------------------------
// JSON
//
// The protocol is five message shapes over one line each, so the worker reads
// and writes them directly rather than linking a JSON library. That keeps the
// dependency set in ppocr/LICENSING.md exactly as it was reviewed: the only
// third-party code in this executable is the engine, OpenCV and what OpenCV
// pulls in. The reader parses a complete JSON object so that a malformed line
// is rejected rather than half-understood, but keeps only the scalar members —
// Kizuna sends sessionId, captureId and imageSize alongside the protocol
// fields, and unknown members must be ignored, not refused.
// ---------------------------------------------------------------------------

constexpr int kMaxJsonDepth = 32;

struct JsonMember {
  enum class Kind { Null, Boolean, Number, String, Composite };

  Kind kind = Kind::Null;
  bool boolean = false;
  double number = 0.0;
  std::string text;

  bool IsString() const { return kind == Kind::String; }

  bool IsInteger() const {
    return kind == Kind::Number && std::isfinite(number) &&
           number == std::floor(number) && std::fabs(number) < 9.0e15;
  }

  long long Integer() const { return static_cast<long long>(number); }
};

class JsonObject {
public:
  void Add(std::string name, JsonMember member) {
    members_.emplace_back(std::move(name), std::move(member));
  }

  const JsonMember *Find(const char *name) const {
    for (const auto &member : members_) {
      if (member.first == name) {
        return &member.second;
      }
    }
    return nullptr;
  }

private:
  std::vector<std::pair<std::string, JsonMember>> members_;
};

class JsonParser {
public:
  explicit JsonParser(const std::string &text) : text_(text) {}

  // Parses the whole line as one JSON object and rejects trailing content, so
  // a truncated or doubled-up line is an error rather than a partial read.
  JsonObject ParseDocument() {
    // Kizuna writes raw UTF-8, but a .NET StreamWriter - which is what drives
    // the worker by hand, and what the verification script uses - emits a byte
    // order mark ahead of its first line. The library the Paddle worker parses
    // with skips one silently; matching that keeps this a drop-in replacement.
    if (text_.compare(0, 3, "\xEF\xBB\xBF") == 0) {
      index_ = 3;
    }
    JsonObject object = ParseObject(0);
    SkipWhitespace();
    if (index_ != text_.size()) {
      Fail();
    }
    return object;
  }

private:
  [[noreturn]] static void Fail() {
    throw std::runtime_error("malformed JSON");
  }

  void SkipWhitespace() {
    while (index_ < text_.size()) {
      const char character = text_[index_];
      if (character != ' ' && character != '\t' && character != '\n' &&
          character != '\r') {
        break;
      }
      ++index_;
    }
  }

  char Peek() {
    SkipWhitespace();
    if (index_ >= text_.size()) {
      Fail();
    }
    return text_[index_];
  }

  void Expect(char expected) {
    if (Peek() != expected) {
      Fail();
    }
    ++index_;
  }

  void ExpectLiteral(const char *literal) {
    const size_t length = std::strlen(literal);
    if (text_.compare(index_, length, literal) != 0) {
      Fail();
    }
    index_ += length;
  }

  static void AppendUtf8(std::string &out, unsigned int code_point) {
    if (code_point < 0x80) {
      out.push_back(static_cast<char>(code_point));
    } else if (code_point < 0x800) {
      out.push_back(static_cast<char>(0xc0 | (code_point >> 6)));
      out.push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
    } else if (code_point < 0x10000) {
      out.push_back(static_cast<char>(0xe0 | (code_point >> 12)));
      out.push_back(static_cast<char>(0x80 | ((code_point >> 6) & 0x3f)));
      out.push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
    } else {
      out.push_back(static_cast<char>(0xf0 | (code_point >> 18)));
      out.push_back(static_cast<char>(0x80 | ((code_point >> 12) & 0x3f)));
      out.push_back(static_cast<char>(0x80 | ((code_point >> 6) & 0x3f)));
      out.push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
    }
  }

  unsigned int ParseHex4() {
    if (index_ + 4 > text_.size()) {
      Fail();
    }
    unsigned int value = 0;
    for (int digit = 0; digit < 4; ++digit) {
      const char character = text_[index_++];
      value <<= 4;
      if (character >= '0' && character <= '9') {
        value |= static_cast<unsigned int>(character - '0');
      } else if (character >= 'a' && character <= 'f') {
        value |= static_cast<unsigned int>(character - 'a' + 10);
      } else if (character >= 'A' && character <= 'F') {
        value |= static_cast<unsigned int>(character - 'A' + 10);
      } else {
        Fail();
      }
    }
    return value;
  }

  std::string ParseString() {
    Expect('"');
    std::string value;
    while (true) {
      if (index_ >= text_.size()) {
        Fail();
      }
      const char character = text_[index_++];
      if (character == '"') {
        return value;
      }
      if (static_cast<unsigned char>(character) < 0x20) {
        Fail();
      }
      if (character != '\\') {
        value.push_back(character);
        continue;
      }
      if (index_ >= text_.size()) {
        Fail();
      }
      switch (text_[index_++]) {
      case '"':
        value.push_back('"');
        break;
      case '\\':
        value.push_back('\\');
        break;
      case '/':
        value.push_back('/');
        break;
      case 'b':
        value.push_back('\b');
        break;
      case 'f':
        value.push_back('\f');
        break;
      case 'n':
        value.push_back('\n');
        break;
      case 'r':
        value.push_back('\r');
        break;
      case 't':
        value.push_back('\t');
        break;
      case 'u': {
        unsigned int code_point = ParseHex4();
        // A lone surrogate is not representable; pair it or reject the line.
        if (code_point >= 0xd800 && code_point <= 0xdbff) {
          if (index_ + 1 >= text_.size() || text_[index_] != '\\' ||
              text_[index_ + 1] != 'u') {
            Fail();
          }
          index_ += 2;
          const unsigned int low = ParseHex4();
          if (low < 0xdc00 || low > 0xdfff) {
            Fail();
          }
          code_point = 0x10000 + ((code_point - 0xd800) << 10) + (low - 0xdc00);
        } else if (code_point >= 0xdc00 && code_point <= 0xdfff) {
          Fail();
        }
        AppendUtf8(value, code_point);
        break;
      }
      default:
        Fail();
      }
    }
  }

  double ParseNumber() {
    const size_t start = index_;
    if (index_ < text_.size() && text_[index_] == '-') {
      ++index_;
    }
    while (index_ < text_.size() &&
           (std::isdigit(static_cast<unsigned char>(text_[index_])) != 0 ||
            text_[index_] == '.' || text_[index_] == 'e' ||
            text_[index_] == 'E' || text_[index_] == '+' ||
            text_[index_] == '-')) {
      ++index_;
    }
    if (index_ == start) {
      Fail();
    }
    const std::string token = text_.substr(start, index_ - start);
    try {
      size_t consumed = 0;
      const double value = std::stod(token, &consumed);
      if (consumed != token.size()) {
        Fail();
      }
      return value;
    } catch (const std::logic_error &) {
      Fail();
    }
  }

  // Reads a value and reports what it was. Objects and arrays are consumed but
  // not retained: nothing the protocol needs is nested.
  JsonMember ParseValue(int depth) {
    if (depth > kMaxJsonDepth) {
      Fail();
    }
    JsonMember member;
    switch (Peek()) {
    case '"':
      member.kind = JsonMember::Kind::String;
      member.text = ParseString();
      return member;
    case '{':
      ParseObject(depth + 1);
      member.kind = JsonMember::Kind::Composite;
      return member;
    case '[':
      ParseArray(depth + 1);
      member.kind = JsonMember::Kind::Composite;
      return member;
    case 't':
      ExpectLiteral("true");
      member.kind = JsonMember::Kind::Boolean;
      member.boolean = true;
      return member;
    case 'f':
      ExpectLiteral("false");
      member.kind = JsonMember::Kind::Boolean;
      member.boolean = false;
      return member;
    case 'n':
      ExpectLiteral("null");
      member.kind = JsonMember::Kind::Null;
      return member;
    default:
      member.kind = JsonMember::Kind::Number;
      member.number = ParseNumber();
      return member;
    }
  }

  void ParseArray(int depth) {
    Expect('[');
    if (Peek() == ']') {
      ++index_;
      return;
    }
    while (true) {
      ParseValue(depth);
      const char separator = Peek();
      ++index_;
      if (separator == ']') {
        return;
      }
      if (separator != ',') {
        Fail();
      }
    }
  }

  JsonObject ParseObject(int depth) {
    if (depth > kMaxJsonDepth) {
      Fail();
    }
    JsonObject object;
    Expect('{');
    if (Peek() == '}') {
      ++index_;
      return object;
    }
    while (true) {
      std::string name = ParseString();
      Expect(':');
      object.Add(std::move(name), ParseValue(depth));
      const char separator = Peek();
      ++index_;
      if (separator == '}') {
        return object;
      }
      if (separator != ',') {
        Fail();
      }
    }
  }

  const std::string &text_;
  size_t index_ = 0;
};

void AppendJsonString(std::string &out, const std::string &value) {
  out.push_back('"');
  for (const char character : value) {
    switch (character) {
    case '"':
      out.append("\\\"");
      break;
    case '\\':
      out.append("\\\\");
      break;
    case '\b':
      out.append("\\b");
      break;
    case '\f':
      out.append("\\f");
      break;
    case '\n':
      out.append("\\n");
      break;
    case '\r':
      out.append("\\r");
      break;
    case '\t':
      out.append("\\t");
      break;
    default:
      // Recognized text is UTF-8 and passes through as bytes; only C0 controls
      // have to be escaped for the line to stay valid JSON.
      if (static_cast<unsigned char>(character) < 0x20) {
        char escape[7];
        std::snprintf(escape, sizeof(escape), "\\u%04x",
                      static_cast<unsigned char>(character));
        out.append(escape);
      } else {
        out.push_back(character);
      }
    }
  }
  out.push_back('"');
}

void AppendJsonInteger(std::string &out, long long value) {
  out.append(std::to_string(value));
}

void AppendJsonConfidence(std::string &out, float value) {
  // Kizuna rejects a region whose confidence is not a finite number in [0, 1],
  // so clamp rather than emit something the client will refuse.
  if (!std::isfinite(value)) {
    value = 0.0f;
  }
  value = (std::min)(1.0f, (std::max)(0.0f, value));
  char formatted[16];
  std::snprintf(formatted, sizeof(formatted), "%.6f",
                static_cast<double>(value));
  out.append(formatted);
}

// ---------------------------------------------------------------------------
// base64
// ---------------------------------------------------------------------------

std::string Base64Decode(const std::string &encoded) {
  static const signed char kValues[256] = {
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63, 52, 53, 54, 55, 56, 57,
      58, 59, 60, 61, -1, -1, -1, -1, -1, -1, -1, 0,  1,  2,  3,  4,  5,  6,
      7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
      25, -1, -1, -1, -1, -1, -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
      37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1};

  std::string decoded;
  decoded.reserve(encoded.size() / 4 * 3);
  unsigned int accumulator = 0;
  int bits = 0;
  size_t padding = 0;
  for (const char character : encoded) {
    if (character == '=') {
      ++padding;
      continue;
    }
    // Kizuna sends one unbroken line, but tolerate the wrapping a hand-written
    // request might carry.
    if (character == '\n' || character == '\r') {
      continue;
    }
    if (padding != 0) {
      throw std::runtime_error("base64 data after padding");
    }
    const signed char value = kValues[static_cast<unsigned char>(character)];
    if (value < 0) {
      throw std::runtime_error("invalid base64 character");
    }
    accumulator = (accumulator << 6) | static_cast<unsigned int>(value);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      decoded.push_back(static_cast<char>((accumulator >> bits) & 0xff));
    }
  }
  if (padding > 2 || (accumulator & ((1u << bits) - 1u)) != 0) {
    throw std::runtime_error("malformed base64 image");
  }
  return decoded;
}

// ---------------------------------------------------------------------------
// Worker
// ---------------------------------------------------------------------------

struct Options {
  int protocol_version = 0;
  std::string language;
  std::string detection_model;
  std::string recognition_model;
  std::string keys;
};

// The engine sets ONNX Runtime's intra- and inter-op thread counts from one
// number, and ONNX Runtime's own default is every logical processor. The spike
// measured that as a 2x loss on an eight-core SMT desktop: 8 threads 79 ms,
// 16 threads 169 ms. Count physical cores instead.
int PhysicalCoreCount() {
  DWORD length = 0;
  GetLogicalProcessorInformationEx(RelationProcessorCore, nullptr, &length);
  if (length == 0) {
    return 0;
  }
  std::vector<unsigned char> buffer(length);
  auto *information =
      reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(buffer.data());
  if (GetLogicalProcessorInformationEx(RelationProcessorCore, information,
                                       &length) == FALSE) {
    return 0;
  }
  int cores = 0;
  for (DWORD offset = 0; offset < length;) {
    const auto *entry =
        reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(
            buffer.data() + offset);
    if (entry->Size == 0) {
      break;
    }
    if (entry->Relationship == RelationProcessorCore) {
      ++cores;
    }
    offset += entry->Size;
  }
  return cores;
}

int DefaultCpuThreads() {
  int cores = PhysicalCoreCount();
  if (cores == 0) {
    // Nothing on a supported Windows reports no cores; halving the logical
    // count is the closest guess if it ever happens.
    const unsigned int logical = std::thread::hardware_concurrency();
    cores = logical == 0 ? 8 : static_cast<int>(logical) / 2;
  }
  return (std::min)(16, (std::max)(1, cores));
}

// RapidOcrOnnx reports model and dictionary setup with plain printf, and stdout
// carries the protocol. Point the C runtime's stdout at stderr for as long as
// the engine is being built, so those lines stay visible to whoever is reading
// the worker's log without ever landing inside a protocol frame. Redirecting
// rather than patching the two call sites keeps ppocr/patches/ — and the
// Apache-2.0 modification notice that enumerates it — unchanged, and covers any
// print the engine grows later.
class StdoutToStderr {
public:
  StdoutToStderr() {
    std::fflush(stdout);
    saved_ = _dup(_fileno(stdout));
    if (saved_ != -1) {
      _dup2(_fileno(stderr), _fileno(stdout));
    }
  }

  ~StdoutToStderr() {
    std::fflush(stdout);
    if (saved_ != -1) {
      _dup2(saved_, _fileno(stdout));
      _close(saved_);
    }
  }

  StdoutToStderr(const StdoutToStderr &) = delete;
  StdoutToStderr &operator=(const StdoutToStderr &) = delete;

private:
  int saved_ = -1;
};

std::string RequiredValue(int argc, char **argv, int &index) {
  if (index + 1 >= argc) {
    throw std::runtime_error(std::string("missing value for ") + argv[index]);
  }
  return argv[++index];
}

Options ParseOptions(int argc, char **argv) {
  Options options;
  for (int index = 1; index < argc; ++index) {
    const std::string name = argv[index];
    if (name == "--protocol-version") {
      options.protocol_version = std::stoi(RequiredValue(argc, argv, index));
    } else if (name == "--lang") {
      options.language = RequiredValue(argc, argv, index);
    } else if (name == "--det-model") {
      options.detection_model = RequiredValue(argc, argv, index);
    } else if (name == "--rec-model") {
      options.recognition_model = RequiredValue(argc, argv, index);
    } else if (name == "--keys") {
      options.keys = RequiredValue(argc, argv, index);
    } else {
      throw std::runtime_error("unknown argument: " + name);
    }
  }

  if (options.protocol_version != kProtocolVersion ||
      options.language != "japan" || options.detection_model.empty() ||
      options.recognition_model.empty() || options.keys.empty()) {
    throw std::runtime_error("invalid worker options");
  }
  return options;
}

bool FileExists(const std::string &path) {
  const DWORD attributes = GetFileAttributesA(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

// The models are .onnx files now rather than the three-file directories Paddle
// Inference wanted.
void ValidateModel(const std::string &path) {
  if (!FileExists(path)) {
    throw std::runtime_error("model file is missing: " + path);
  }
}

void ValidateDictionary(const std::string &path) {
  std::ifstream input(path);
  if (!input) {
    throw std::runtime_error("dictionary file is missing: " + path);
  }
  size_t entries = 0;
  std::string line;
  while (std::getline(input, line)) {
    ++entries;
  }
  if (entries != kDictionaryEntries) {
    throw std::runtime_error("dictionary has " + std::to_string(entries) +
                             " entries, expected " +
                             std::to_string(kDictionaryEntries));
  }
}

void Emit(const std::string &message) {
  std::cout << message << '\n';
  std::cout.flush();
}

void EmitError(bool has_request_id = false, long long request_id = 0) {
  std::string message = "{\"version\":";
  AppendJsonInteger(message, kProtocolVersion);
  message.append(",\"type\":\"error\"");
  if (has_request_id) {
    message.append(",\"requestId\":");
    AppendJsonInteger(message, request_id);
  }
  message.push_back('}');
  Emit(message);
}

struct Region {
  std::string text;
  float confidence = 0.0f;
  std::vector<cv::Point> quad;
};

// The detector and the recogniser, held together for the life of the process so
// their sessions and weights are paid for once.
class Engine {
public:
  Engine(const Options &options, int cpu_threads) {
    // setNumThread configures the session options, so both calls have to come
    // before the sessions are created.
    detection_.setNumThread(cpu_threads);
    recognition_.setNumThread(cpu_threads);
    const StdoutToStderr quiet;
    detection_.initModel(options.detection_model);
    recognition_.initModel(options.recognition_model, options.keys);
  }

  std::vector<Region> Run(cv::Mat &image) {
    ScaleParam scale = getScaleParam(image, kDetectionSideLength);
    std::vector<TextBox> boxes = detection_.getTextBoxes(
        image, scale, kBoxScoreThreshold, kBoxThreshold, kUnclipRatio);

    std::vector<cv::Mat> crops;
    std::vector<std::vector<cv::Point>> quads;
    crops.reserve(boxes.size());
    quads.reserve(boxes.size());
    for (const TextBox &box : boxes) {
      if (!IsCroppable(box.boxPoint)) {
        continue;
      }
      crops.push_back(getRotateCropImage(image, box.boxPoint));
      quads.push_back(box.boxPoint);
    }

    const std::vector<TextLine> lines = recognition_.getTextLinesBatched(
        crops, kRecognitionBatchSize, kRecognitionWidth);

    std::vector<Region> regions;
    regions.reserve(lines.size());
    for (size_t index = 0; index < lines.size() && index < quads.size();
         ++index) {
      // An empty line carries nothing and Kizuna discards it on arrival.
      if (lines[index].text.empty()) {
        continue;
      }
      Region region;
      region.text = lines[index].text;
      region.confidence = MeanScore(lines[index].charScores);
      region.quad = quads[index];
      regions.push_back(std::move(region));
    }
    SortRegions(regions);
    if (regions.size() > static_cast<size_t>(kMaxRegions)) {
      regions.resize(kMaxRegions);
    }
    return regions;
  }

  // A crop, unconditionally, so that the recogniser session is exercised even
  // when detection found nothing in the frame it was given.
  void RunRecognition(cv::Mat &image) {
    std::vector<cv::Mat> crops{image};
    recognition_.getTextLinesBatched(crops, kRecognitionBatchSize,
                                     kRecognitionWidth);
  }

private:
  // getRotateCropImage crops the bounding rectangle and warps the quadrilateral
  // into it. Either step raises an OpenCV error on a degenerate box, which
  // would fail the whole capture, so those are dropped here instead.
  static bool IsCroppable(const std::vector<cv::Point> &quad) {
    if (quad.size() != 4) {
      return false;
    }
    int left = quad[0].x;
    int right = quad[0].x;
    int top = quad[0].y;
    int bottom = quad[0].y;
    for (const cv::Point &point : quad) {
      left = (std::min)(left, point.x);
      right = (std::max)(right, point.x);
      top = (std::min)(top, point.y);
      bottom = (std::max)(bottom, point.y);
    }
    if (right - left < kMinimumCropSide || bottom - top < kMinimumCropSide) {
      return false;
    }
    return SideLength(quad[0], quad[1]) >= kMinimumCropSide &&
           SideLength(quad[0], quad[3]) >= kMinimumCropSide;
  }

  static int SideLength(const cv::Point &from, const cv::Point &to) {
    const double dx = static_cast<double>(to.x - from.x);
    const double dy = static_cast<double>(to.y - from.y);
    return static_cast<int>(std::sqrt(dx * dx + dy * dy));
  }

  // Recognition confidence, the way the protocol has always meant it: the mean
  // of the per-character scores. The detector's box score is a different
  // measurement and is not a substitute for it.
  static float MeanScore(const std::vector<float> &scores) {
    if (scores.empty()) {
      return 0.0f;
    }
    double total = 0.0;
    for (const float score : scores) {
      total += static_cast<double>(score);
    }
    return static_cast<float>(total / static_cast<double>(scores.size()));
  }

  // PaddleOCR orders detections top-to-bottom and then left-to-right before it
  // recognises them; RapidOcrOnnx returns them in contour order. Reproducing
  // the order here keeps the region sequence the payload emits the same as the
  // one it emits today. This is PaddleOCR's own two-phase sort: order by the
  // top-left corner, then let a neighbouring box on the same line overtake one
  // that starts further right.
  static void SortRegions(std::vector<Region> &regions) {
    constexpr int kSameLineTolerance = 10;
    std::stable_sort(regions.begin(), regions.end(),
                     [](const Region &left, const Region &right) {
                       if (left.quad[0].y != right.quad[0].y) {
                         return left.quad[0].y < right.quad[0].y;
                       }
                       return left.quad[0].x < right.quad[0].x;
                     });
    for (size_t index = 0; index + 1 < regions.size(); ++index) {
      for (size_t candidate = index + 1; candidate-- > 0;) {
        const cv::Point &current = regions[candidate].quad[0];
        const cv::Point &next = regions[candidate + 1].quad[0];
        if (std::abs(next.y - current.y) >= kSameLineTolerance ||
            next.x >= current.x) {
          break;
        }
        std::swap(regions[candidate], regions[candidate + 1]);
      }
    }
  }

  DbNet detection_;
  CrnnNet recognition_;
};

// A small strip rather than a real capture: on CPU the first inference costs no
// more than a warm one, so this only has to take both sessions through one Run
// before the handshake. It is not comparable to a recognition time.
void WarmUp(Engine &engine) {
  cv::Mat image(96, 384, CV_8UC3, cv::Scalar(255, 255, 255));
  cv::putText(image, "Kizuna 123", cv::Point(12, 64), cv::FONT_HERSHEY_SIMPLEX,
              1.3, cv::Scalar(0, 0, 0), 2, cv::LINE_AA);
  if (engine.Run(image).empty()) {
    engine.RunRecognition(image);
  }
}

std::string Recognize(Engine &engine, const JsonObject &request) {
  const JsonMember *version = request.Find("version");
  const JsonMember *type = request.Find("type");
  const JsonMember *request_id = request.Find("requestId");
  const JsonMember *image_base64 = request.Find("imageBase64");
  if (version == nullptr || !version->IsInteger() ||
      version->Integer() != kProtocolVersion || type == nullptr ||
      !type->IsString() || type->text != "recognize" || request_id == nullptr ||
      !request_id->IsInteger() || image_base64 == nullptr ||
      !image_base64->IsString()) {
    throw std::runtime_error("invalid recognition request");
  }

  const std::string bytes = Base64Decode(image_base64->text);
  if (bytes.empty()) {
    throw std::runtime_error("image is empty");
  }

  // No temporary file: PaddleOCR's batch sampler dispatched on a file suffix
  // and forced every capture through the disk. ONNX Runtime takes the decoded
  // matrix directly.
  const cv::Mat encoded(1, static_cast<int>(bytes.size()), CV_8UC1,
                        const_cast<char *>(bytes.data()));
  cv::Mat image = cv::imdecode(encoded, cv::IMREAD_COLOR);
  if (image.empty()) {
    throw std::runtime_error("unsupported image format");
  }

  const std::vector<Region> regions = engine.Run(image);

  std::string message = "{\"version\":";
  AppendJsonInteger(message, kProtocolVersion);
  message.append(",\"type\":\"result\",\"requestId\":");
  AppendJsonInteger(message, request_id->Integer());
  message.append(",\"regions\":[");
  for (size_t index = 0; index < regions.size(); ++index) {
    if (index != 0) {
      message.push_back(',');
    }
    message.append("{\"text\":");
    AppendJsonString(message, regions[index].text);
    message.append(",\"confidence\":");
    AppendJsonConfidence(message, regions[index].confidence);
    message.append(",\"quad\":[");
    for (size_t point = 0; point < regions[index].quad.size(); ++point) {
      if (point != 0) {
        message.push_back(',');
      }
      message.push_back('[');
      AppendJsonInteger(message, regions[index].quad[point].x);
      message.push_back(',');
      AppendJsonInteger(message, regions[index].quad[point].y);
      message.push_back(']');
    }
    message.append("]}");
  }
  message.append("]}");
  return message;
}

} // namespace

int main(int argc, char **argv) {
  std::ios::sync_with_stdio(false);

  try {
    const Options options = ParseOptions(argc, argv);
    ValidateModel(options.detection_model);
    ValidateModel(options.recognition_model);
    ValidateDictionary(options.keys);

    Engine engine(options, DefaultCpuThreads());
    WarmUp(engine);

    std::string ready = "{\"version\":";
    AppendJsonInteger(ready, kProtocolVersion);
    ready.append(",\"type\":\"ready\"}");
    Emit(ready);

    std::string line;
    while (std::getline(std::cin, line)) {
      if (line.empty()) {
        continue;
      }
      bool has_request_id = false;
      long long request_id = 0;
      try {
        JsonParser parser(line);
        const JsonObject request = parser.ParseDocument();
        const JsonMember *identifier = request.Find("requestId");
        if (identifier != nullptr && identifier->IsInteger()) {
          has_request_id = true;
          request_id = identifier->Integer();
        }
        Emit(Recognize(engine, request));
      } catch (const std::exception &error) {
        // The protocol's error frame carries no reason, and a worker that
        // rejects a capture without saying why cannot be diagnosed from a log.
        // stderr is not the protocol, so the reason goes there.
        std::cerr << "request failed: " << error.what() << '\n';
        EmitError(has_request_id, request_id);
      } catch (...) {
        std::cerr << "request failed\n";
        EmitError(has_request_id, request_id);
      }
    }
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    EmitError();
    return 2;
  }
}
