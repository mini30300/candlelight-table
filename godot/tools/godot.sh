#!/usr/bin/env bash
# godot.sh — fetch the pinned Godot editor binary and, on request, the export templates. CI (godot.yml) and local
# setups both use it. Every download is checked against the SHA-512 pinned below; files already in place and
# correct are kept, so running it again costs nothing.
#
#   bash godot/tools/godot.sh                            # ~/godot-bin/godot (linux x86_64 or arm64, from `uname -m`)
#   bash godot/tools/godot.sh templates                  # + all export templates → ~/.local/share/godot/export_templates/4.7.1.stable
#   bash godot/tools/godot.sh templates windows android  # only the Windows x86_64 and Android ones (smaller CI cache)
#                                                        groups: windows, android, linux, all
# Env: GODOT_BIN_DIR, GODOT_TEMPLATES_DIR (defaults above); GODOT_DL_CACHE: a folder holding already-downloaded
#      archives under their official names (used only when the checksum matches); GODOT_VERSION / GODOT_RELEASE.
# The last line printed on stdout is the path of the binary.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.1}"
GODOT_RELEASE="${GODOT_RELEASE:-stable}"
GODOT_URL="${GODOT_URL:-https://github.com/godotengine/godot/releases/download}"
BIN_DIR="${GODOT_BIN_DIR:-$HOME/godot-bin}"
TPL_DIR="${GODOT_TEMPLATES_DIR:-$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}}"
TAG="${GODOT_VERSION}-${GODOT_RELEASE}"

# SHA-512 of the release files, copied from the official SHA512-SUMS.txt attached to the GitHub release
# (https://github.com/godotengine/godot/releases/download/4.7.1-stable/SHA512-SUMS.txt, read on 2026-10-06).
# An engine bump is a dedicated PR (ARCHITECTURE §11) that replaces these three values from the new SHA512-SUMS.txt.
sha512_for() {
  case "$1" in
    Godot_v4.7.1-stable_linux.x86_64.zip) echo 4ccdab7a48eeccbe8819a2fc1f6262f8d72065d98601bcb3743fcbd7ebd39f373758a788ee3293a05ec5b2c48538266c437404312e372225cd2df273945a2de9 ;;
    Godot_v4.7.1-stable_linux.arm64.zip) echo de64efe4d936ac0403769e078a73d961a9c647cab04168c5fb5a7fe33728e200a67324ed99368eeb27964e205e72a61e48efb63b52d5de34d12dd6a95ca0fc45 ;;
    Godot_v4.7.1-stable_export_templates.tpz) echo afcc83d8d3d298038f19c58744a0d660fa75dd4baa33cb55d1011bb2565a2a8c2381728924564cb909e37c205a23f21b521b23bd057993afd43ae4da0b2f9d47 ;;
    *) echo "" ;;
  esac
}

say() { echo "godot.sh: $*" >&2; }
die() { say "ERROR: $*"; exit 1; }

# verify FILE NAME → true when FILE has the pinned SHA-512 of the release file NAME
verify() {
  local want
  want=$(sha512_for "$2")
  [ -n "$want" ] || die "no pinned checksum for $2 (GODOT_VERSION=$GODOT_VERSION): add it to sha512_for()"
  echo "$want  $1" | sha512sum -c --quiet - > /dev/null 2>&1
}

# fetch NAME → prints the path of a verified copy of the release file NAME (download cache first, then GitHub)
fetch() {
  local name="$1" out="$DL_DIR/$1"
  if [ -n "${GODOT_DL_CACHE:-}" ] && [ -s "$GODOT_DL_CACHE/$name" ]; then
    if verify "$GODOT_DL_CACHE/$name" "$name"; then
      say "using $GODOT_DL_CACHE/$name (checksum ok)"
      echo "$GODOT_DL_CACHE/$name"
      return
    fi
    say "$GODOT_DL_CACHE/$name has the wrong checksum, downloading instead"
  fi
  if [ -s "$out" ] && verify "$out" "$name"; then
    echo "$out"
    return
  fi
  say "downloading $GODOT_URL/$TAG/$name"
  curl -fsSL --retry 3 --retry-delay 5 -o "$out" "$GODOT_URL/$TAG/$name"
  verify "$out" "$name" || die "checksum mismatch for $name (got $(sha512sum "$out" | cut -c1-32)…): not installing"
  echo "$out"
}

# version_of BINARY → the version line it prints ("4.7.1.stable.official.a13da4feb"), empty when it does not run
version_of() {
  local v
  v=$("$1" --version 2> /dev/null | tail -n 1) || true
  echo "$v"
}

DL_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/godot-dl"
mkdir -p "$DL_DIR"

# --- the editor binary (it also runs headless: import, tests, exports) ---------------------------------------
arch=$(uname -m)
case "$arch" in
  x86_64 | amd64) arch=x86_64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) die "unsupported architecture $arch (linux x86_64 and arm64 only)" ;;
esac
bin="$BIN_DIR/godot"
want="${GODOT_VERSION}.${GODOT_RELEASE}."
case "$(version_of "$bin")" in
  "$want"*)
    say "binary already there: $bin ($(version_of "$bin"))"
    ;;
  *)
    zip=$(fetch "Godot_v${TAG}_linux.${arch}.zip")
    mkdir -p "$BIN_DIR"
    rm -f "$bin"
    unzip -q -o "$zip" "Godot_v${TAG}_linux.${arch}" -d "$BIN_DIR"
    mv "$BIN_DIR/Godot_v${TAG}_linux.${arch}" "$bin"
    chmod +x "$bin"
    case "$(version_of "$bin")" in
      "$want"*) say "installed $bin ($(version_of "$bin"))" ;;
      *) die "$bin does not report ${want}* (got '$(version_of "$bin")')" ;;
    esac
    ;;
esac

# --- export templates, optional ------------------------------------------------------------------------------
if [ "${1:-}" = "templates" ]; then
  shift
  groups=("$@")
  [ ${#groups[@]} -gt 0 ] || groups=(all)
  patterns=(templates/version.txt)
  markers=()
  for g in "${groups[@]}"; do
    case "$g" in
      windows) patterns+=('templates/windows_*x86_64*'); markers+=(windows_release_x86_64.exe windows_debug_x86_64.exe) ;;
      android) patterns+=(templates/android_debug.apk templates/android_release.apk); markers+=(android_release.apk android_debug.apk) ;;
      linux) patterns+=('templates/linux_*'); markers+=(linux_release.x86_64 linux_release.arm64) ;;
      all) patterns=('templates/*'); markers+=(windows_release_x86_64.exe android_release.apk linux_release.x86_64 macos.zip web_release.zip) ;;
      *) die "unknown template group '$g' (windows, android, linux, all)" ;;
    esac
  done
  have=1
  { [ -s "$TPL_DIR/version.txt" ] && grep -q "^${GODOT_VERSION}\.${GODOT_RELEASE}$" "$TPL_DIR/version.txt"; } || have=0
  for m in "${markers[@]}"; do
    [ -s "$TPL_DIR/$m" ] || have=0
  done
  if [ "$have" = 1 ]; then
    say "templates already there: $TPL_DIR (${groups[*]})"
  else
    tpz=$(fetch "Godot_v${TAG}_export_templates.tpz")
    mkdir -p "$TPL_DIR"
    unzip -q -o -j "$tpz" "${patterns[@]}" -d "$TPL_DIR"
    for m in "${markers[@]}"; do
      [ -s "$TPL_DIR/$m" ] || die "template $m missing after unzip"
    done
    say "templates installed: $TPL_DIR ($(ls "$TPL_DIR" | wc -l) files: ${groups[*]})"
  fi
fi

echo "$bin"
