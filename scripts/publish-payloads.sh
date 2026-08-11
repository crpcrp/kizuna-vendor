#!/usr/bin/env bash
# Packages the vendor payloads into per-platform archives and attaches them to a
# GitHub release, which is how Kizuna consumes this mirror.
#
# Git LFS is not the delivery channel. Every `git lfs pull` a build performs is
# billed against the account's LFS bandwidth quota, and a full mirror is ~855 MB
# regardless of which platform is being built, so a handful of releases a month
# exhausts it. Release assets are not metered that way, compress to roughly half
# the size, and can be fetched with a plain HTTPS GET that needs no credential,
# no git, and no LFS client.
#
# The archive is laid out exactly like this repository, so `resources.lock.json`
# keeps its existing `from` paths and Kizuna's verification is unchanged: it
# still hashes every staged file and cross-checks manifest.json and
# SHA256SUMS.txt, both of which travel inside the archive.
#
# Usage:
#   scripts/publish-payloads.sh [--platform win32-x64|linux-x64|all]
#                               [--tag <tag>] [--out <dir>] [--dry-run] [--replace]
#
# Normally run through .github/workflows/publish-payloads.yml, which gets a
# scoped GITHUB_TOKEN and leaves an audit trail. Running it locally needs a
# GitHub CLI login with write access to this repository.
#
# Requires: bash, tar, gzip, sha256sum (or shasum), and the GitHub CLI for
# anything other than --dry-run. Runs on Linux and in Git Bash on Windows; file
# modes are not carried by the archive because Kizuna applies them from
# resources.lock.json's `executable` flag when it stages.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

platform=all
tag=""
out_dir="dist"
dry_run=0
replace=0

while [ $# -gt 0 ]; do
  case "$1" in
    --platform) platform="${2:?--platform needs a value}"; shift 2 ;;
    --tag) tag="${2:?--tag needs a value}"; shift 2 ;;
    --out) out_dir="${2:?--out needs a value}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --replace) replace=1; shift ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}" | cut -c3-; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$platform" in
  all|win32-x64|linux-x64) ;;
  *) echo "unknown platform: $platform" >&2; exit 2 ;;
esac

commit="$(git rev-parse HEAD)"
short="$(git rev-parse --short=12 HEAD)"
: "${tag:=payloads-$short}"

# Metadata Kizuna reads out of the extracted archive, not just payload bytes.
metadata=(manifest.json SHA256SUMS.txt)

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# A pointer packaged by mistake would produce an archive that extracts cleanly,
# passes tar, and fails every hash check on the consumer's machine. Catch it
# here, where the fix is `git lfs pull`.
assert_not_lfs_pointer() {
  local path="$1"
  local size
  size="$(wc -c <"$path")"
  if [ "$size" -lt 2048 ] && head -c 42 "$path" | grep -q '^version https://git-lfs.github.com/spec/v1'; then
    echo "  $path is an unresolved Git LFS pointer" >&2
    return 1
  fi
  return 0
}

# Every payload file that SHA256SUMS.txt knows about is re-hashed before it is
# packaged. The seven Windows licence texts predate that file and are checked
# for existence only.
#
# What is packaged must also be what the commit says, because the lock pins a
# commit alongside the archive hash; an edited working tree would publish bytes
# no revision of this repository ever contained.
verify_tree() {
  local problems=0 path expected actual
  if ! git diff --quiet HEAD -- "$@" "${metadata[@]}" ||
    [ -n "$(git ls-files --others --exclude-standard -- "$@")" ]; then
    echo "Uncommitted changes under: $* ${metadata[*]}" >&2
    echo "An archive must correspond to a commit; commit or stash them first." >&2
    exit 1
  fi
  echo "Verifying $* against SHA256SUMS.txt"
  while IFS= read -r path; do
    if ! assert_not_lfs_pointer "$path"; then problems=$((problems + 1)); continue; fi
    expected="$(awk -v want="$path" '{ p = $2; sub(/^\*/, "", p); if (p == want) print $1 }' SHA256SUMS.txt)"
    [ -n "$expected" ] || continue
    actual="$(sha256_of "$path")"
    if [ "$actual" != "$expected" ]; then
      echo "  $path does not match SHA256SUMS.txt" >&2
      problems=$((problems + 1))
    fi
  done < <(git ls-files -- "$@")
  if [ "$problems" -gt 0 ]; then
    echo "$problems problem(s); refusing to package" >&2
    exit 1
  fi
}

# --sort, --mtime and the ownership flags make the archive a pure function of
# the tree, so republishing the same commit yields the same SHA-256. gzip -n
# keeps the filename and timestamp out of the container for the same reason.
pack() {
  local archive="$1"; shift
  echo "Packing $archive"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -cf - -- "$@" | gzip -9 -n >"$archive"
}

trees_for() {
  case "$1" in
    win32-x64)
      # paddleocr is only present once its payload has landed.
      local dirs=(ffmpeg mecab mpv)
      [ -d paddleocr ] && dirs+=(paddleocr)
      printf '%s\n' "${dirs[@]}"
      ;;
    linux-x64) printf '%s\n' linux-x64 ;;
  esac
}

mkdir -p "$out_dir"
targets=()
[ "$platform" = all ] && targets=(win32-x64 linux-x64) || targets=("$platform")

declare -a summary=()
for target in "${targets[@]}"; do
  mapfile -t trees < <(trees_for "$target")
  verify_tree "${trees[@]}"
  archive="$out_dir/kizuna-vendor-$target.tar.gz"
  pack "$archive" "${metadata[@]}" "${trees[@]}"
  size="$(wc -c <"$archive" | tr -d ' ')"
  digest="$(sha256_of "$archive")"
  summary+=("$target|$(basename "$archive")|$digest|$size")
  printf '  %s  %s bytes\n' "$digest" "$size"
done

echo
echo "resources.lock.json source block for commit $commit:"
for row in "${summary[@]}"; do
  IFS='|' read -r target asset digest size <<<"$row"
  cat <<JSON
  "$target": {
    "source": {
      "repo": "crpcrp/kizuna-vendor",
      "commit": "$commit",
      "manifest": "manifest.json",
      "checksums": "SHA256SUMS.txt",
      "archive": { "release": "$tag", "asset": "$asset", "sha256": "$digest", "size": $size }
    }
  }
JSON
done

if [ "$dry_run" -eq 1 ]; then
  echo
  echo "--dry-run: archives are in $out_dir/ and nothing was published."
  exit 0
fi

# An asset that is already published may be pinned by a resources.lock.json
# somewhere, and overwriting it would silently break every consumer holding that
# hash. Replacing one is a deliberate act, not a retry default.
echo
if gh release view "$tag" >/dev/null 2>&1; then
  published="$(gh release view "$tag" --json assets --jq '.assets[].name')"
  collisions=()
  for row in "${summary[@]}"; do
    IFS='|' read -r _ asset _ _ <<<"$row"
    if printf '%s\n' "$published" | grep -qx -- "$asset"; then collisions+=("$asset"); fi
  done
  if [ "${#collisions[@]}" -gt 0 ] && [ "$replace" -eq 0 ]; then
    echo "Release $tag already carries: ${collisions[*]}" >&2
    echo "Publish a new commit instead, or pass --replace if the existing asset" >&2
    echo "is genuinely wrong and nothing has pinned it yet." >&2
    exit 1
  fi
  echo "Release $tag already exists; adding assets"
else
  echo "Creating release $tag at $commit"
  gh release create "$tag" \
    --target "$commit" \
    --title "Vendor payloads $short" \
    --notes "Runtime payloads for kizuna-vendor at \`$commit\`.

Consumed by Kizuna's \`npm run resources\` through \`resources.lock.json\`; the
archives are laid out exactly like the repository and carry \`manifest.json\`
and \`SHA256SUMS.txt\` for verification. Not intended for direct download."
fi

for row in "${summary[@]}"; do
  IFS='|' read -r target asset digest size <<<"$row"
  if [ "$replace" -eq 1 ]; then
    gh release upload "$tag" "$out_dir/$asset" --clobber
  else
    gh release upload "$tag" "$out_dir/$asset"
  fi
done

echo
echo "Published $tag"
