# Linux x64 baseline and dependencies

## Supported baseline

The payload targets Ubuntu 24.04 LTS (Noble) on x86-64, the current
`ubuntu-latest` generation used for Kizuna release builds. The minimum runtime
baseline is glibc 2.39, libstdc++ from GCC 13, and the X11-capable desktop stack
shipped by Ubuntu 24.04. This is stricter than Electron 43's own Linux minimum
and gives one testable distro contract for the native helper programs.

The payload is not advertised as a generic cross-distribution tarball. A `.deb`
must express the package dependencies below. AppImage or unpacked builds must
either bundle the same libraries themselves or require an Ubuntu 24.04-compatible
host with the two exact packages installed.

## Loader policy

The mirrored mpv, FFmpeg, and ffprobe executables are unmodified files extracted
from Ubuntu's signed archive packages. Their non-baseline libraries are supplied
by these exact package dependencies:

```text
mpv (= 0.37.0-1ubuntu4)
ffmpeg (= 7:6.1.1-3ubuntu5)
```

The exact direct `Depends` fields used by those packages are:

```text
mpv: libarchive13t64 (>= 3.4.0), libasound2t64 (>= 1.0.27), libass9 (>= 1:0.15.0), libavcodec60 (>= 7:6.1), libavdevice60 (>= 7:6.0), libavfilter9 (>= 7:6.0), libavformat60 (>= 7:6.0), libavutil58 (>= 7:6.0), libbluray2 (>= 1:0.2.2), libc6 (>= 2.38), libcaca0 (>= 0.99.beta20), libcdio-cdda2t64 (>= 10.2+2.0.0), libcdio-paranoia2t64 (>= 10.2+2.0.0), libcdio19t64 (>= 2.1.0), libdrm2 (>= 2.4.105), libdvdnav4 (>= 4.1.3), libegl1, libgbm1 (>= 17.1.0~rc2), libjack-jackd2-0 (>= 1.9.10+20150825) | libjack-0.125, libjpeg8 (>= 8c), liblcms2-2 (>= 2.6), liblua5.2-0 (>= 5.2.4), libmujs3 (>= 1.0.7), libpipewire-0.3-0t64 (>= 0.3.50), libplacebo338 (>= 6.338.1), libpulse0 (>= 0.99.4), librubberband2 (>= 3.3.0+dfsg), libsdl2-2.0-0 (>= 2.0.12), libsixel1 (>= 1.10.3), libswresample4 (>= 7:6.0), libswscale7 (>= 7:6.0), libuchardet0 (>= 0.0.1), libva-drm2 (>= 1.1.0), libva-wayland2 (>= 1.3.0), libva-x11-2 (>= 1.0.3), libva2 (>= 2.2.0), libvdpau1 (>= 0.2), libvulkan1 (>= 1.2.131.2), libwayland-client0 (>= 1.20.0), libwayland-cursor0 (>= 1.15.0), libwayland-egl1 (>= 1.15.0), libx11-6 (>= 2:1.2.99.901), libxext6, libxkbcommon0 (>= 0.5.0), libxpresent1, libxrandr2 (>= 2:1.4.0), libxss1, libxv1, libzimg2 (>= 0.3.1), zlib1g (>= 1:1.1.4)
ffmpeg: libavcodec60 (>= 7:6.1), libavdevice60 (>= 7:6.0), libavfilter9 (>= 7:6.0), libavformat60 (>= 7:6.0), libavutil58 (>= 7:6.0), libc6 (>= 2.35), libpostproc57 (>= 7:6.0), libsdl2-2.0-0 (>= 2.0.12), libswresample4 (>= 7:6.0), libswscale7 (>= 7:6.0)
```

`linux-x64/mecab/bin/mecab` is a POSIX wrapper. It prepends the adjacent
`../lib` directory to `LD_LIBRARY_PATH`, runs the unmodified Ubuntu executable
`mecab.bin`, and selects the adjacent UTF-8 IPADIC through `../etc/mecabrc`.
Both the SONAME and fully versioned copies of `libmecab.so.2.0.0` are mirrored
as regular files so Git checkouts do not depend on symlink support. That library
needs only baseline `libc6 (>= 2.38)`, `libgcc-s1 (>= 3.3.1)`, and
`libstdc++6 (>= 13.1)`.

## Audit

Run `scripts/verify-linux-x64.sh` after `git lfs pull`. It checks hashes and
executable modes, runs all four tools, tokenizes a Japanese fixture, verifies
the `libmp3lame` encoder, verifies mpv's `--wid` option and X11 EGL/Vulkan
contexts, and runs `file` plus `ldd` on every ELF executable.
