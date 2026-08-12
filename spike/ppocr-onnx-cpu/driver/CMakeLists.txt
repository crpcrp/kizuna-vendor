cmake_minimum_required(VERSION 3.20)
project(ocrspike CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

# Which onnxruntime package to link: the CPU-only nuget or the DirectML one.
set(ORT_DIR "" CACHE PATH "extracted onnxruntime nuget root")
option(USE_DIRECTML "link the DirectML build of onnxruntime" OFF)

set(RAPID_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../RapidOcrOnnx" CACHE PATH "patched RapidOcrOnnx checkout")
set(RAPID "${RAPID_DIR}")

find_package(OpenCV REQUIRED
    PATHS "${CMAKE_CURRENT_SOURCE_DIR}/../deps/opencv-min/x64/vc18/staticlib" NO_DEFAULT_PATH)

add_executable(ocrspike
    main.cpp
    ${RAPID}/src/DbNet.cpp
    ${RAPID}/src/CrnnNet.cpp
    ${RAPID}/src/OcrUtils.cpp
    ${RAPID}/src/clipper.cpp
)

target_include_directories(ocrspike PRIVATE
    ${RAPID}/include
    ${ORT_DIR}/build/native/include
    ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(ocrspike PRIVATE
    ${OpenCV_LIBS}
    ${ORT_DIR}/runtimes/win-x64/native/onnxruntime.lib
    dxgi
    psapi
)

if (USE_DIRECTML)
    target_compile_definitions(ocrspike PRIVATE __DIRECTML__)
endif ()

target_compile_definitions(ocrspike PRIVATE _CRT_SECURE_NO_WARNINGS NOMINMAX)
