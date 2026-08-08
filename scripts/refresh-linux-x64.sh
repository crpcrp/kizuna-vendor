#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
payload_dir="$work_dir/linux-x64"
trap 'rm -rf "$work_dir"' EXIT

if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
  echo "This recipe must run on an amd64 Debian-family system." >&2
  exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_CODENAME:-}" != "noble" ]]; then
  echo "This recipe is pinned to Ubuntu 24.04 LTS (noble)." >&2
  exit 1
fi

mkdir -p "$work_dir/debs"
cd "$work_dir/debs"
apt-get download \
  'mpv=0.37.0-1ubuntu4' \
  'ffmpeg=7:6.1.1-3ubuntu5' \
  'mecab=0.996-14ubuntu4' \
  'mecab-utils=0.996-14ubuntu4' \
  'libmecab2=0.996-14ubuntu4' \
  'mecab-ipadic=2.7.0-20070801+main-3' \
  'mecab-ipadic-utf8=2.7.0-20070801+main-3'

sha256sum --check <<'CHECKSUMS'
1a23baace5f2688a47e28119aedae6993cd638e6279a7227dfc52d9a337a1c17  ffmpeg_7%3a6.1.1-3ubuntu5_amd64.deb
cc91804dc82ac766833a97288384b7b65762aa26212bb915a556e13430c61745  libmecab2_0.996-14ubuntu4_amd64.deb
a7f5fa4f63ac6e766c3162ea3abfff04532288d7e341cfb6ffd8c5a6cd8f8bf9  mecab-ipadic-utf8_2.7.0-20070801+main-3_all.deb
82e538f2015959972b649359159d2984e6d47514d503c9edb5fbda2631a09c50  mecab-ipadic_2.7.0-20070801+main-3_all.deb
8b1fa63b945364e94af81fb35d2c4efe192f2d7feda919c349adb7cfae33e9eb  mecab-utils_0.996-14ubuntu4_amd64.deb
b2b273a40ca0baf818b384a6fe408c9bda8306c11450cfa3f4987115330ca1b5  mecab_0.996-14ubuntu4_amd64.deb
26b9273c3cc4c69b55ad908d168c624b95fd6785ea96625143e344b53e786e94  mpv_0.37.0-1ubuntu4_amd64.deb
CHECKSUMS

for package in *.deb; do
  package_root="$work_dir/root-${package%.deb}"
  mkdir -p "$package_root"
  dpkg-deb --extract "$package" "$package_root"
done

mpv_root="$work_dir/root-mpv_0.37.0-1ubuntu4_amd64"
ffmpeg_root="$work_dir/root-ffmpeg_7%3a6.1.1-3ubuntu5_amd64"
mecab_root="$work_dir/root-mecab_0.996-14ubuntu4_amd64"
mecab_utils_root="$work_dir/root-mecab-utils_0.996-14ubuntu4_amd64"
libmecab_root="$work_dir/root-libmecab2_0.996-14ubuntu4_amd64"
ipadic_root="$work_dir/root-mecab-ipadic_2.7.0-20070801+main-3_all"

install -d \
  "$payload_dir/mpv/bin" "$payload_dir/mpv/licenses" \
  "$payload_dir/ffmpeg/bin" "$payload_dir/ffmpeg/licenses" \
  "$payload_dir/mecab/bin" "$payload_dir/mecab/lib" \
  "$payload_dir/mecab/etc" "$payload_dir/mecab/ipadic" \
  "$payload_dir/mecab/licenses"

install -m 0755 "$mpv_root/usr/bin/mpv" "$payload_dir/mpv/bin/mpv"
install -m 0644 "$mpv_root/usr/share/doc/mpv/copyright" \
  "$payload_dir/mpv/licenses/COPYRIGHT.Ubuntu"
install -m 0644 /usr/share/common-licenses/GPL-2 \
  "$payload_dir/mpv/licenses/GPL-2.txt"
install -m 0644 /usr/share/common-licenses/LGPL-2.1 \
  "$payload_dir/mpv/licenses/LGPL-2.1.txt"

install -m 0755 "$ffmpeg_root/usr/bin/ffmpeg" "$payload_dir/ffmpeg/bin/ffmpeg"
install -m 0755 "$ffmpeg_root/usr/bin/ffprobe" "$payload_dir/ffmpeg/bin/ffprobe"
install -m 0644 "$ffmpeg_root/usr/share/doc/ffmpeg/copyright" \
  "$payload_dir/ffmpeg/licenses/COPYRIGHT.Ubuntu"
install -m 0644 /usr/share/common-licenses/GPL-2 \
  "$payload_dir/ffmpeg/licenses/GPL-2.txt"
install -m 0644 /usr/share/common-licenses/GPL-3 \
  "$payload_dir/ffmpeg/licenses/GPL-3.txt"
install -m 0644 /usr/share/common-licenses/LGPL-2 \
  "$payload_dir/ffmpeg/licenses/LGPL-2.txt"
install -m 0644 /usr/share/common-licenses/LGPL-2.1 \
  "$payload_dir/ffmpeg/licenses/LGPL-2.1.txt"

install -m 0755 "$mecab_root/usr/bin/mecab" "$payload_dir/mecab/bin/mecab.bin"
install -m 0644 "$libmecab_root/usr/lib/x86_64-linux-gnu/libmecab.so.2.0.0" \
  "$payload_dir/mecab/lib/libmecab.so.2.0.0"
install -m 0644 "$libmecab_root/usr/lib/x86_64-linux-gnu/libmecab.so.2.0.0" \
  "$payload_dir/mecab/lib/libmecab.so.2"

LD_LIBRARY_PATH="$libmecab_root/usr/lib/x86_64-linux-gnu" \
  "$mecab_utils_root/usr/lib/mecab/mecab-dict-index" \
  -d "$ipadic_root/usr/share/mecab/dic/ipadic" \
  -o "$payload_dir/mecab/ipadic" -f EUC-JP -t UTF-8
sed 's/EUC-JP/UTF-8/g' "$ipadic_root/usr/share/mecab/dic/ipadic/dicrc" \
  > "$payload_dir/mecab/ipadic/dicrc"

install -m 0644 "$mecab_root/usr/share/doc/mecab/copyright" \
  "$payload_dir/mecab/licenses/COPYRIGHT.MeCab-Ubuntu"
install -m 0644 "$libmecab_root/usr/share/doc/libmecab2/copyright" \
  "$payload_dir/mecab/licenses/COPYRIGHT.libmecab-Ubuntu"
install -m 0644 "$ipadic_root/usr/share/doc/mecab-ipadic/copyright" \
  "$payload_dir/mecab/licenses/COPYRIGHT.IPADIC-Ubuntu"
install -m 0644 /usr/share/common-licenses/GPL-2 \
  "$payload_dir/mecab/licenses/GPL-2.txt"
install -m 0644 /usr/share/common-licenses/LGPL-2.1 \
  "$payload_dir/mecab/licenses/LGPL-2.1.txt"

cat > "$payload_dir/mecab/bin/mecab" <<'WRAPPER'
#!/bin/sh
set -eu
bin_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
lib_dir="$bin_dir/../lib"
if [ -n "${LD_LIBRARY_PATH:-}" ]; then
  export LD_LIBRARY_PATH="$lib_dir:$LD_LIBRARY_PATH"
else
  export LD_LIBRARY_PATH="$lib_dir"
fi
exec "$bin_dir/mecab.bin" -r "$bin_dir/../etc/mecabrc" "$@"
WRAPPER
chmod 0755 "$payload_dir/mecab/bin/mecab"

cat > "$payload_dir/mecab/etc/mecabrc" <<'MECABRC'
dicdir = $(rcpath)/../ipadic
MECABRC

rm -rf "$repo_root/linux-x64"
mv "$payload_dir" "$repo_root/linux-x64"

echo "Refreshed $repo_root/linux-x64"
