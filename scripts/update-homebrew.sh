#!/bin/bash
# Update the Homebrew formula after a new release.
# Usage: ./scripts/update-homebrew.sh 0.1.0

set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
REPO="tijs/ladder"
TAP_REPO="tijs/homebrew-tap"
FORMULA="Formula/ladder.rb"

echo "Fetching checksum for v${VERSION}..."

ARM_URL="https://github.com/${REPO}/releases/download/v${VERSION}/ladder-${VERSION}-aarch64-apple-darwin.tar.gz"
ARM_SHA=$(curl -sL "$ARM_URL" | shasum -a 256 | cut -d' ' -f1)

echo "ARM64 SHA256: ${ARM_SHA}"

TMPDIR=$(mktemp -d)
gh repo clone "$TAP_REPO" "$TMPDIR"

cd "$TMPDIR"

sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$FORMULA"
sed -i '' "s/sha256 \".*\"/sha256 \"${ARM_SHA}\"/" "$FORMULA"

echo ""
echo "Updated formula:"
cat "$FORMULA"
echo ""

git add "$FORMULA"
git commit -m "ladder ${VERSION}"
git push origin main

rm -rf "$TMPDIR"

echo "Done. Homebrew formula updated to v${VERSION}."
