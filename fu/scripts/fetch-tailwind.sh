#!/bin/sh
# Build-only Linux helper: GitHub release headers exceed httpc's 10 KiB limit.
# Keep this version aligned with config/config.exs; fetch the same official asset.
set -eu
cd -- "$(dirname -- "$0")/.."
version=4.1.12
case "$(uname -s):$(uname -m)" in
  Linux:x86_64) target=linux-x64 ;;
  Linux:aarch64|Linux:arm64) target=linux-arm64 ;;
  *) echo 'This build helper supports Linux x64/arm64 containers and CI.' >&2; exit 1 ;;
esac
mkdir -p _build
destination="_build/tailwind-$target"
if [ -x "$destination" ]; then exit 0; fi
temporary=$(mktemp "$destination.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --retry 3 --connect-timeout 30 --max-time 180 \
  --output "$temporary" \
  "https://github.com/tailwindlabs/tailwindcss/releases/download/v$version/tailwindcss-$target"
chmod 755 "$temporary"
case "$(NO_COLOR=1 "$temporary" --help)" in
  *"tailwindcss v$version"*) ;;
  *) echo 'The downloaded Tailwind version does not match the build.' >&2; exit 1 ;;
esac
mv "$temporary" "$destination"
