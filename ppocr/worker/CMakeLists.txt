# Copyright (C) 2026 Kizuna contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds ppocr.exe: Kizuna's JSONL worker linked against the four RapidOcrOnnx
# sources that make up the detection and recognition pipeline, a statically
# linked minimal OpenCV, and ONNX Runtime.
#
# Upstream's own CMakeLists is deliberately not used. It builds its `main.cpp`
# command-line tool, the JNI and C bindings and the AngleNet stage none of which
# this payload wants, and it expects prebuilt libraries from RapidAI's release
# repositories rather than the official Microsoft NuGet. Linking the four
# sources from a target we own is smaller than patching all that out, and it
# means the patches in ppocr/patches/ stay about the pipeline itself.
#
# Everything is driven from scripts/build-ppocr-onnx-win-x64.ps1, which pins and
# verifies each input; the cache variables below are the interface to it.

cmake_minimum_required(VERSION 3.20)
project(ppocr_worker CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The static CRT is a size decision and a licensing one: it is what removes the
# VC redistributable DLLs from the payload entirely, and ppocr/LICENSING.md is
# written on that basis. It must also match the OpenCV built alongside it.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

set(ENGINE_DIR "" CACHE PATH "the patched RapidOcrOnnx checkout")
set(ORT_INCLUDE_DIR "" CACHE PATH "the ONNX Runtime C/C++ headers")
set(ORT_LIBRARY "" CACHE FILEPATH "the ONNX Runtime import library")

# Fail here rather than with a missing-header error twenty lines into the build.
foreach(required ENGINE_DIR ORT_INCLUDE_DIR ORT_LIBRARY)
  if(NOT ${required})
    message(FATAL_ERROR "${required} must be set; run scripts/build-ppocr-onnx-win-x64.ps1")
  endif()
endforeach()

# OpenCV_DIR points at the staticlib configuration the build script installs.
find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)

add_executable(ppocr
  ppocr_worker.cc
  ${ENGINE_DIR}/src/DbNet.cpp
  ${ENGINE_DIR}/src/CrnnNet.cpp
  ${ENGINE_DIR}/src/OcrUtils.cpp
  ${ENGINE_DIR}/src/clipper.cpp
)

target_include_directories(ppocr PRIVATE
  ${ENGINE_DIR}/include
  ${ORT_INCLUDE_DIR}
  ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(ppocr PRIVATE ${OpenCV_LIBS} ${ORT_LIBRARY})

# NOMINMAX is defined by the worker itself; upstream's sources need only this.
target_compile_definitions(ppocr PRIVATE _CRT_SECURE_NO_WARNINGS)
