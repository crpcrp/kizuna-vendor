// Copyright (C) 2026 Kizuna contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#define NOMINMAX
#include <Windows.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "src/pipelines/ocr/pipeline.h"
#include "src/utils/ilogger.h"
#include "third_party/nlohmann/json.hpp"

namespace {

using json = nlohmann::json;

constexpr int kProtocolVersion = 1;
constexpr int kMaxRegions = 512;

struct Options {
  int protocol_version = 0;
  std::string language;
  std::string detection_model;
  std::string recognition_model;
  // Tuning knobs. The defaults are what Kizuna ships; they are exposed so the
  // latency of a payload can be swept without rebuilding the worker.
  std::string detection_model_name = "PP-OCRv5_mobile_det";
  std::string recognition_model_name = "PP-OCRv5_mobile_rec";
  int cpu_threads = 0;
  int recognition_batch_size = 6;
  int detection_side_length = 960;
  // Recognition crops vary in width, so every frame presents oneDNN with fresh
  // input shapes. PaddleOCR's default cache of 10 primitives thrashes and each
  // region pays full primitive construction; a roomy cache keeps them warm.
  int mkldnn_cache_capacity = 512;
};

int DefaultCpuThreads() {
  const unsigned int cores = std::thread::hardware_concurrency();
  if (cores == 0) {
    return 8;
  }
  return static_cast<int>(std::min(cores, 16u));
}

// PaddleOCR's batch sampler dispatches on the file suffix and rejects anything
// outside {jpg, jpeg, png, bmp}, so the temporary image has to be named after
// the format the client actually sent.
const char *SniffImageExtension(const std::string &bytes) {
  const auto starts_with = [&bytes](const char *signature, size_t length) {
    return bytes.size() >= length &&
           std::memcmp(bytes.data(), signature, length) == 0;
  };
  if (starts_with("\x89PNG\r\n\x1a\n", 8)) {
    return ".png";
  }
  if (starts_with("\xff\xd8\xff", 3)) {
    return ".jpg";
  }
  if (starts_with("BM", 2)) {
    return ".bmp";
  }
  return nullptr;
}

class TempFile {
public:
  TempFile(const std::string &bytes, const char *extension) {
    char temp_path[MAX_PATH + 1] = {};
    char file_path[MAX_PATH + 1] = {};
    const DWORD temp_length = GetTempPathA(MAX_PATH, temp_path);
    if (temp_length == 0 || temp_length >= MAX_PATH ||
        GetTempFileNameA(temp_path, "kzo", 0, file_path) == 0) {
      throw std::runtime_error("could not create a temporary image path");
    }
    // GetTempFileNameA reserves a .tmp placeholder; drop it and keep the
    // suffixed name so the sampler recognises the file.
    std::remove(file_path);
    path_ = std::string(file_path) + extension;
    std::ofstream output(path_, std::ios::binary | std::ios::trunc);
    output.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    if (!output) {
      std::remove(path_.c_str());
      throw std::runtime_error("could not write the temporary image");
    }
  }

  ~TempFile() { std::remove(path_.c_str()); }

  const std::string &path() const { return path_; }

  TempFile(const TempFile &) = delete;
  TempFile &operator=(const TempFile &) = delete;

private:
  std::string path_;
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
    } else if (name == "--det-model-name") {
      options.detection_model_name = RequiredValue(argc, argv, index);
    } else if (name == "--rec-model-name") {
      options.recognition_model_name = RequiredValue(argc, argv, index);
    } else if (name == "--cpu-threads") {
      options.cpu_threads = std::stoi(RequiredValue(argc, argv, index));
    } else if (name == "--rec-batch-size") {
      options.recognition_batch_size = std::stoi(RequiredValue(argc, argv, index));
    } else if (name == "--det-side-len") {
      options.detection_side_length = std::stoi(RequiredValue(argc, argv, index));
    } else if (name == "--mkldnn-cache") {
      options.mkldnn_cache_capacity = std::stoi(RequiredValue(argc, argv, index));
    } else {
      throw std::runtime_error("unknown argument: " + name);
    }
  }

  if (options.protocol_version != kProtocolVersion ||
      options.language != "japan" || options.detection_model.empty() ||
      options.recognition_model.empty() ||
      options.recognition_batch_size < 1 ||
      options.detection_side_length < 32 ||
      options.mkldnn_cache_capacity < 1) {
    throw std::runtime_error("invalid worker options");
  }
  if (options.cpu_threads < 1) {
    options.cpu_threads = DefaultCpuThreads();
  }
  return options;
}

bool FileExists(const std::string &path) {
  const DWORD attributes = GetFileAttributesA(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

void ValidateModel(const std::string &directory) {
  for (const char *name : {"inference.json", "inference.pdiparams",
                           "inference.yml"}) {
    if (!FileExists(directory + "\\" + name)) {
      throw std::runtime_error(std::string("model file is missing: ") + name);
    }
  }
}

void Emit(const json &message) {
  std::cout << message.dump() << '\n';
  std::cout.flush();
}

void EmitError(const json *request = nullptr) {
  json message = {{"version", kProtocolVersion}, {"type", "error"}};
  if (request != nullptr && request->contains("requestId") &&
      (*request)["requestId"].is_number_integer()) {
    message["requestId"] = (*request)["requestId"];
  }
  Emit(message);
}

OCRPipelineParams MakePipelineParams(const Options &options) {
  OCRPipelineParams params;
  params.text_detection_model_name = options.detection_model_name;
  params.text_detection_model_dir = options.detection_model;
  params.text_recognition_model_name = options.recognition_model_name;
  params.text_recognition_model_dir = options.recognition_model;
  params.use_doc_orientation_classify = false;
  params.use_doc_unwarping = false;
  params.use_textline_orientation = false;
  params.lang = options.language;
  params.ocr_version = "PP-OCRv5";
  params.enable_mkldnn = true;
  params.mkldnn_cache_capacity = options.mkldnn_cache_capacity;
  params.cpu_threads = options.cpu_threads;
  params.thread_num = 1;
  params.paddlex_config = Utility::PaddleXConfigVariant(
      std::unordered_map<std::string, std::string>{
          {"pipeline_name", "OCR"},
          {"text_type", "general"},
          {"use_doc_orientation_classify", "False"},
          {"use_doc_unwarping", "False"},
          {"use_textline_orientation", "False"},
          {"SubModules.TextDetection.model_name", options.detection_model_name},
          {"SubModules.TextDetection.model_dir", options.detection_model},
          {"SubModules.TextDetection.batch_size", "1"},
          {"SubModules.TextDetection.limit_side_len",
           std::to_string(options.detection_side_length)},
          {"SubModules.TextDetection.limit_type", "max"},
          {"SubModules.TextDetection.max_side_limit", "4000"},
          {"SubModules.TextDetection.thresh", "0.3"},
          {"SubModules.TextDetection.box_thresh", "0.6"},
          {"SubModules.TextDetection.unclip_ratio", "1.5"},
          {"SubModules.TextRecognition.model_name",
           options.recognition_model_name},
          {"SubModules.TextRecognition.model_dir", options.recognition_model},
          {"SubModules.TextRecognition.batch_size",
           std::to_string(options.recognition_batch_size)},
          {"SubModules.TextRecognition.score_thresh", "0.0"}});
  return params;
}

void WarmUp(_OCRPipeline &pipeline) {
  cv::Mat image(96, 384, CV_8UC3, cv::Scalar(255, 255, 255));
  cv::putText(image, "Kizuna 123", cv::Point(12, 64), cv::FONT_HERSHEY_SIMPLEX,
              1.3, cv::Scalar(0, 0, 0), 2, cv::LINE_AA);
  std::vector<uchar> encoded;
  if (!cv::imencode(".png", image, encoded)) {
    throw std::runtime_error("could not encode the warm-up image");
  }
  TempFile warmup(std::string(encoded.begin(), encoded.end()), ".png");
  pipeline.Predict(std::vector<std::string>{warmup.path()});
}

json Recognize(_OCRPipeline &pipeline, const json &request) {
  if (request.value("version", 0) != kProtocolVersion ||
      request.value("type", std::string()) != "recognize" ||
      !request.contains("requestId") ||
      !request["requestId"].is_number_integer() ||
      !request.contains("imageBase64") ||
      !request["imageBase64"].is_string()) {
    throw std::runtime_error("invalid recognition request");
  }

  const std::string bytes =
      iLogger::base64_decode(request["imageBase64"].get<std::string>());
  if (bytes.empty()) {
    throw std::runtime_error("image is empty");
  }
  const char *extension = SniffImageExtension(bytes);
  if (extension == nullptr) {
    throw std::runtime_error("unsupported image format");
  }

  TempFile image(bytes, extension);
  pipeline.Predict(std::vector<std::string>{image.path()});
  const std::vector<OCRPipelineResult> results = pipeline.PipelineResult();
  if (results.size() != 1) {
    throw std::runtime_error("OCR returned an unexpected result count");
  }

  const OCRPipelineResult &result = results.front();
  const size_t region_count =
      std::min({result.rec_texts.size(), result.rec_scores.size(),
                result.rec_polys.size(), static_cast<size_t>(kMaxRegions)});
  json regions = json::array();
  for (size_t index = 0; index < region_count; ++index) {
    const std::vector<cv::Point2f> &polygon = result.rec_polys[index];
    if (polygon.size() != 4) {
      continue;
    }
    json quad = json::array();
    for (const cv::Point2f &point : polygon) {
      quad.push_back({point.x, point.y});
    }
    regions.push_back({{"text", result.rec_texts[index]},
                       {"confidence", result.rec_scores[index]},
                       {"quad", quad}});
  }

  return {{"version", kProtocolVersion},
          {"type", "result"},
          {"requestId", request["requestId"]},
          {"regions", regions}};
}

} // namespace

int main(int argc, char **argv) {
  std::ios::sync_with_stdio(false);
  iLogger::set_log_level(iLogger::LogLevel::Error);
  _putenv_s("GLOG_minloglevel", "3");

  try {
    const Options options = ParseOptions(argc, argv);
    ValidateModel(options.detection_model);
    ValidateModel(options.recognition_model);

    _OCRPipeline pipeline(MakePipelineParams(options));
    WarmUp(pipeline);
    Emit({{"version", kProtocolVersion}, {"type", "ready"}});

    std::string line;
    while (std::getline(std::cin, line)) {
      if (line.empty()) {
        continue;
      }
      json request;
      try {
        request = json::parse(line);
        Emit(Recognize(pipeline, request));
      } catch (...) {
        EmitError(&request);
      }
    }
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    EmitError();
    return 2;
  }
}
