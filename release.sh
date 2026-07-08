#!/usr/bin/env bash
# release.sh — Build, sign, tag, and publish a new Shortsify release
#
# Usage:
#   bash release.sh            # auto-bumps patch version (1.0.0 → 1.0.1)
#   bash release.sh 1.2.0      # explicit version

set -euo pipefail
cd "$(dirname "$0")"

# ── Version ───────────────────────────────────────────────────────────────────
if [[ ${1:-} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    VERSION="$1"
else
    # Bump patch from latest git tag (default v1.0.0 if no tags exist)
    LATEST=$(git tag --list "v*" | sort -V | tail -1)
    if [[ -z "$LATEST" ]]; then
        VERSION="1.0.0"
    else
        IFS='.' read -r major minor patch <<< "${LATEST#v}"
        VERSION="${major}.${minor}.$((patch + 1))"
    fi
fi
TAG="v$VERSION"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Releasing Shortsify $TAG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Confirm ───────────────────────────────────────────────────────────────────
read -r -p "Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Update version in download.html ──────────────────────────────────────────
echo ""
echo "▶ Updating version in docs/download.html…"
sed -i '' "s/v[0-9]*\.[0-9]*\.[0-9]*/v${VERSION}/g" docs/download.html
sed -i '' "s/v[0-9]*\.[0-9]*\.[0-9]*/v${VERSION}/g" docs/index.html

# ── Build app + DMG ──────────────────────────────────────────────────────────
echo ""
echo "▶ Building app…"
bash build-app.sh

# ── Commit any changes (source files only, not build artifacts) ───────────────
echo ""
echo "▶ Committing changes…"
git add Sources/ docs/ Package.swift build-app.sh make-icon.swift make-dmg-bg.swift release.sh .gitignore 2>/dev/null || true
if git diff --cached --quiet; then
    echo "  (nothing to commit)"
else
    git commit -m "Release $TAG"
fi

# ── Tag ───────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Creating tag $TAG…"
git tag -a "$TAG" -m "Shortsify $TAG"

# ── Push ──────────────────────────────────────────────────────────────────────
echo ""
echo "▶ Pushing to GitHub…"
git push origin main
git push origin "$TAG"

# ── GitHub Release ────────────────────────────────────────────────────────────
echo ""
echo "▶ Creating GitHub release…"

# Check gh CLI is available
if ! command -v gh &> /dev/null; then
    echo ""
    echo "⚠️  'gh' CLI not found. Install it with: brew install gh"
    echo "   Then run: gh release create $TAG Shortsify.dmg --title \"Shortsify $TAG\" --generate-notes"
    exit 0
fi

gh release create "$TAG" \
    Shortsify.dmg \
    --title "Shortsify $TAG" \
    --generate-notes

echo ""
echo "✅ Done! Release $TAG is live."
echo "   https://github.com/yooyplay/shortsify/releases/tag/$TAG"
