// Spike driver for kizuna-vendor issue #11.
//
// Drives the (patched) RapidOcrOnnx DbNet + CrnnNet directly, without the
// AngleNet stage the shipped Kizuna worker does not use, and reports the
// numbers the issue asks for: time-to-ready, first-request cost, p50/p95 over
// repeated captures, peak working set, GPU memory delta, and the ONNX Runtime
// profile file that shows which provider each node ran on.

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <numeric>
#include <string>
#include <vector>

#include <windows.h>
#include <psapi.h>
#include <dxgi1_4.h>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include "DbNet.h"
#include "CrnnNet.h"
#include "OcrUtils.h"

namespace {

double nowMs() {
    using clock = std::chrono::steady_clock;
    return std::chrono::duration<double, std::milli>(clock::now().time_since_epoch()).count();
}

size_t peakWorkingSetBytes() {
    PROCESS_MEMORY_COUNTERS pmc{};
    pmc.cb = sizeof(pmc);
    GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc));
    return pmc.PeakWorkingSetSize;
}

// Local (dedicated VRAM) usage of this process on the given adapter.
long long gpuLocalUsageBytes(int adapterIndex) {
    IDXGIFactory4 *factory = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory4), (void **) &factory))) return -1;
    IDXGIAdapter1 *adapter1 = nullptr;
    long long used = -1;
    if (SUCCEEDED(factory->EnumAdapters1((UINT) adapterIndex, &adapter1))) {
        IDXGIAdapter3 *adapter3 = nullptr;
        if (SUCCEEDED(adapter1->QueryInterface(__uuidof(IDXGIAdapter3), (void **) &adapter3))) {
            DXGI_QUERY_VIDEO_MEMORY_INFO info{};
            if (SUCCEEDED(adapter3->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &info))) {
                used = (long long) info.CurrentUsage;
            }
            adapter3->Release();
        }
        adapter1->Release();
    }
    factory->Release();
    return used;
}

void listAdapters() {
    IDXGIFactory4 *factory = nullptr;
    if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory4), (void **) &factory))) {
        printf("adapters: CreateDXGIFactory1 failed\n");
        return;
    }
    IDXGIAdapter1 *adapter = nullptr;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
        DXGI_ADAPTER_DESC1 desc{};
        adapter->GetDesc1(&desc);
        char name[256];
        WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, name, sizeof(name), nullptr, nullptr);
        printf("adapter[%u] %s  vram=%llu MB  software=%d\n", i, name,
               (unsigned long long) (desc.DedicatedVideoMemory / (1024 * 1024)),
               (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) ? 1 : 0);
        adapter->Release();
    }
    factory->Release();
}

double percentile(std::vector<double> v, double p) {
    if (v.empty()) return 0;
    std::sort(v.begin(), v.end());
    // Nearest-rank; with 20+ samples this is the honest reading of p95.
    size_t idx = (size_t) std::ceil(p / 100.0 * v.size());
    if (idx == 0) idx = 1;
    if (idx > v.size()) idx = v.size();
    return v[idx - 1];
}

struct Options {
    std::string det, rec, keys, image, profilePrefix;
    int adapter = -1;      // -1 => CPU provider
    int threads = 0;       // 0 => ORT default
    int maxSide = 960;
    int runs = 20;
    int recBatch = 0;   // 0 => upstream one-region-per-Run path
    int recWidth = 320;
    float boxScoreThresh = 0.5f;
    float boxThresh = 0.3f;
    float unClipRatio = 1.6f;
    bool listAdaptersOnly = false;
};

} // namespace

int main(int argc, char **argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() { return std::string(i + 1 < argc ? argv[++i] : ""); };
        if (a == "--det") o.det = next();
        else if (a == "--rec") o.rec = next();
        else if (a == "--keys") o.keys = next();
        else if (a == "--image") o.image = next();
        else if (a == "--adapter") o.adapter = std::stoi(next());
        else if (a == "--threads") o.threads = std::stoi(next());
        else if (a == "--max-side") o.maxSide = std::stoi(next());
        else if (a == "--runs") o.runs = std::stoi(next());
        else if (a == "--rec-batch") o.recBatch = std::stoi(next());
        else if (a == "--rec-width") o.recWidth = std::stoi(next());
        else if (a == "--box-score-thresh") o.boxScoreThresh = std::stof(next());
        else if (a == "--box-thresh") o.boxThresh = std::stof(next());
        else if (a == "--unclip-ratio") o.unClipRatio = std::stof(next());
        else if (a == "--profile") o.profilePrefix = next();
        else if (a == "--list-adapters") o.listAdaptersOnly = true;
        else { printf("unknown argument %s\n", a.c_str()); return 2; }
    }

    SetConsoleOutputCP(CP_UTF8);
    // Unbuffered, so a hard crash inside a provider still leaves the log that
    // says which stage we reached.
    setvbuf(stdout, nullptr, _IONBF, 0);

    if (o.listAdaptersOnly) { listAdapters(); return 0; }

#ifdef __DIRECTML__
    printf("build: DirectML-enabled onnxruntime\n");
#else
    printf("build: CPU-only onnxruntime\n");
    if (o.adapter >= 0) {
        printf("FATAL: --adapter requires the DirectML build\n");
        return 2;
    }
#endif
    printf("provider request: %s\n", o.adapter >= 0 ? "DML" : "CPU");

    long long gpuBefore = o.adapter >= 0 ? gpuLocalUsageBytes(o.adapter) : -1;

    // ---- time to ready: construct sessions and warm them once ----
    double t0 = nowMs();
    DbNet dbNet;
    CrnnNet crnnNet;
    dbNet.setNumThread(o.threads);
    crnnNet.setNumThread(o.threads);

    double tProviderStart = nowMs();
    try {
        dbNet.setGpuIndex(o.adapter);
        crnnNet.setGpuIndex(o.adapter);
    } catch (const Ort::Exception &e) {
        printf("STAGE_FAILURE append_provider: %s\n", e.what());
        return 3;
    }
    double tProviderEnd = nowMs();
    printf("append provider: %.1f ms\n", tProviderEnd - tProviderStart);

    if (!o.profilePrefix.empty()) {
        dbNet.enableProfiling(o.profilePrefix + "-det");
        crnnNet.enableProfiling(o.profilePrefix + "-rec");
    }

    double tSessStart = nowMs();
    try {
        dbNet.initModel(o.det);
    } catch (const Ort::Exception &e) {
        printf("STAGE_FAILURE create_det_session: %s\n", e.what());
        return 4;
    }
    double tDetSession = nowMs();
    try {
        crnnNet.initModel(o.rec, o.keys);
    } catch (const Ort::Exception &e) {
        printf("STAGE_FAILURE create_rec_session: %s\n", e.what());
        return 5;
    }
    double tRecSession = nowMs();
    printf("create det session: %.1f ms\n", tDetSession - tSessStart);
    printf("create rec session: %.1f ms\n", tRecSession - tDetSession);

    // Kizuna hands the worker an encoded capture per request, so PNG decode is
    // part of the real per-request cost even though it is not inference.
    double tDecode = nowMs();
    cv::Mat src = cv::imread(o.image, cv::IMREAD_COLOR);
    double decodeMs = nowMs() - tDecode;
    if (src.empty()) { printf("FATAL: could not read %s\n", o.image.c_str()); return 2; }
    printf("image: %dx%d (png decode %.1f ms)\n", src.cols, src.rows, decodeMs);

    ScaleParam scale = getScaleParam(src, o.maxSide);
    printf("det input: %dx%d (max-side %d)\n", scale.dstWidth, scale.dstHeight, o.maxSide);
    if (o.recBatch > 0) printf("rec mode: batched %d x 3x48x%d\n", o.recBatch, o.recWidth);
    else printf("rec mode: upstream, one region per Run, variable width\n");

    auto runOnce = [&](std::vector<std::string> *outText, double *detMs, double *recMs) {
        double a = nowMs();
        std::vector<TextBox> boxes;
        try {
            boxes = dbNet.getTextBoxes(src, scale, o.boxScoreThresh, o.boxThresh, o.unClipRatio);
        } catch (const Ort::Exception &e) {
            printf("STAGE_FAILURE run_det: %s\n", e.what());
            exit(6);
        }
        double b = nowMs();
        std::vector<cv::Mat> parts;
        parts.reserve(boxes.size());
        for (auto &box : boxes) parts.emplace_back(getRotateCropImage(src, box.boxPoint));
        std::vector<TextLine> lines;
        try {
            lines = o.recBatch > 0 ? crnnNet.getTextLinesBatched(parts, o.recBatch, o.recWidth)
                                   : crnnNet.getTextLines(parts, nullptr, nullptr);
        } catch (const Ort::Exception &e) {
            printf("STAGE_FAILURE run_rec: %s\n", e.what());
            exit(7);
        }
        double c = nowMs();
        *detMs = b - a;
        *recMs = c - b;
        if (outText) { for (auto &l : lines) outText->push_back(l.text); }
        return c - a;
    };

    // ---- first inference (cold): this is where DirectML compiles shaders ----
    std::vector<std::string> firstText;
    double detMs = 0, recMs = 0;
    double first = runOnce(&firstText, &detMs, &recMs);
    double ready = nowMs() - t0;
    printf("time to ready (construct + sessions + first inference): %.1f ms\n", ready);
    printf("first inference: %.1f ms (det %.1f ms, rec %.1f ms over %zu regions)\n",
           first, detMs, recMs, firstText.size());

    printf("--- recognized (first run) ---\n");
    for (size_t i = 0; i < firstText.size(); ++i) printf("[%zu] %s\n", i, firstText[i].c_str());
    printf("--- end recognized ---\n");

    // ---- warm loop ----
    std::vector<double> totals, dets, recs;
    std::vector<std::string> lastText;
    for (int i = 0; i < o.runs; ++i) {
        lastText.clear();
        double d = 0, r = 0;
        totals.push_back(runOnce(&lastText, &d, &r));
        dets.push_back(d);
        recs.push_back(r);
    }
    if (!totals.empty()) {
        double mean = std::accumulate(totals.begin(), totals.end(), 0.0) / totals.size();
        printf("warm runs: %d\n", (int) totals.size());
        printf("warm total  mean %.1f  p50 %.1f  p95 %.1f  min %.1f  max %.1f ms\n",
               mean, percentile(totals, 50), percentile(totals, 95),
               *std::min_element(totals.begin(), totals.end()),
               *std::max_element(totals.begin(), totals.end()));
        printf("warm det    p50 %.1f  p95 %.1f ms\n", percentile(dets, 50), percentile(dets, 95));
        printf("warm rec    p50 %.1f  p95 %.1f ms\n", percentile(recs, 50), percentile(recs, 95));
    }

    printf("--- recognized (last warm run) ---\n");
    for (size_t i = 0; i < lastText.size(); ++i) printf("[%zu] %s\n", i, lastText[i].c_str());
    printf("--- end recognized ---\n");

    printf("peak working set: %.1f MB\n", peakWorkingSetBytes() / (1024.0 * 1024.0));
    if (o.adapter >= 0) {
        long long after = gpuLocalUsageBytes(o.adapter);
        printf("gpu local memory: before %.1f MB, after %.1f MB, delta %.1f MB\n",
               gpuBefore / (1024.0 * 1024.0), after / (1024.0 * 1024.0),
               (after - gpuBefore) / (1024.0 * 1024.0));
    }

    if (!o.profilePrefix.empty()) {
        printf("profile det: %s\n", dbNet.endProfiling().c_str());
        printf("profile rec: %s\n", crnnNet.endProfiling().c_str());
    }
    return 0;
}
