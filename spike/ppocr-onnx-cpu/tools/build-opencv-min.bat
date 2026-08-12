@echo off
rem Minimal static OpenCV for the ppocr worker: core, imgproc, imgcodecs (PNG
rem only), static CRT, no IPP/OpenCL/protobuf/video. The official prebuilt
rem Windows package ships no staticlib set any more, and its opencv_world DLL
rem is 76 MB, so the payload size story depends on building this ourselves.
rem
rem Result on the spike machine: the linked worker executable is 4.7 MB total,
rem OpenCV included.
rem
rem   build-opencv-min.bat <opencv-sources-dir> <build-dir> <install-prefix>

setlocal
if "%~3"=="" (
  echo usage: build-opencv-min.bat ^<sources^> ^<build^> ^<install-prefix^>
  exit /b 2
)

call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
set CMAKE="C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

%CMAKE% -S %1 -B %2 -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_INSTALL_PREFIX=%3 ^
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded ^
  -DBUILD_SHARED_LIBS=OFF ^
  -DBUILD_LIST=core,imgproc,imgcodecs ^
  -DBUILD_opencv_apps=OFF -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF ^
  -DBUILD_JAVA=OFF -DBUILD_opencv_python2=OFF -DBUILD_opencv_python3=OFF -DBUILD_opencv_js=OFF ^
  -DBUILD_ZLIB=ON -DBUILD_PNG=ON ^
  -DBUILD_JPEG=OFF -DBUILD_TIFF=OFF -DBUILD_WEBP=OFF -DBUILD_OPENJPEG=OFF -DBUILD_JASPER=OFF -DBUILD_OPENEXR=OFF ^
  -DWITH_JPEG=OFF -DWITH_TIFF=OFF -DWITH_WEBP=OFF -DWITH_OPENJPEG=OFF -DWITH_JASPER=OFF -DWITH_OPENEXR=OFF -DWITH_AVIF=OFF -DWITH_GIF=OFF -DWITH_SPNG=OFF ^
  -DWITH_IPP=OFF -DWITH_OPENCL=OFF -DWITH_PROTOBUF=OFF -DWITH_FFMPEG=OFF -DWITH_MSMF=OFF -DWITH_DSHOW=OFF ^
  -DWITH_EIGEN=OFF -DWITH_ADE=OFF -DWITH_QUIRC=OFF -DWITH_LAPACK=OFF -DWITH_VTK=OFF -DWITH_ITT=OFF -DWITH_OBSENSOR=OFF ^
  -DVIDEOIO_ENABLE_PLUGINS=OFF -DHIGHGUI_ENABLE_PLUGINS=OFF -DOPENCV_ENABLE_NONFREE=OFF ^
  -DCV_TRACE=OFF -DOPENCV_GENERATE_PKGCONFIG=OFF -DOPENCV_GENERATE_SETUPVARS=OFF
if errorlevel 1 exit /b 1

%CMAKE% --build %2 --target install
