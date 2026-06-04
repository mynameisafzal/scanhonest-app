#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-branches.sh  —  Run AFTER committing everything to main
#
# Creates:
#   design   branch  ← Design/ folder only
#   testing  branch  ← ScanHonestTests/ + ScanHonestUITests/ only
#
# main stays clean with only Swift architecture source.
# ─────────────────────────────────────────────────────────────────────────────
set -e
cd "$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         ScanHonest Branch Setup Script               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Safety: must be on main with no uncommitted changes ──────────────────────
CURRENT=$(git branch --show-current)
if [[ "$CURRENT" != "main" ]]; then
  echo "❌  Must be on main branch. Currently on: $CURRENT"
  echo "    Run: git checkout main"
  exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "❌  Uncommitted changes detected. Commit everything first:"
  echo ""
  echo "    git add -A"
  echo '    git commit -m "feat: initial full source commit"'
  echo ""
  git status --short
  exit 1
fi

echo "✓ On main, working tree clean."
echo ""

# ── Helper: create or reset a branch from main ───────────────────────────────
make_branch() {
  local BRANCH=$1
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "  Branch '$BRANCH' already exists — skipping creation."
    echo "  To recreate: git branch -D $BRANCH && bash setup-branches.sh"
  else
    git checkout -b "$BRANCH" main
    echo "  ✓ Created branch: $BRANCH"
    git checkout main
  fi
}

# ── 1. main: apply .gitignore, remove Design+Tests from tracking ──────────────
echo "── Step 1: Clean up main — untrack Design/ and test targets ──"

# Remove Design/, test dirs from git index (keeps files on disk)
git rm -r --cached Design/              2>/dev/null && echo "  Untracked Design/" || echo "  Design/ already untracked"
git rm -r --cached ScanHonestTests/     2>/dev/null && echo "  Untracked ScanHonestTests/" || echo "  ScanHonestTests/ already untracked"
git rm -r --cached ScanHonestUITests/   2>/dev/null && echo "  Untracked ScanHonestUITests/" || echo "  ScanHonestUITests/ already untracked"

# Also remove common junk if tracked
git rm --cached ScanHonest/_navfix.txt  2>/dev/null || true
git rm -r --cached AppStore/Screenshots/ 2>/dev/null || true

# Commit the cleanup (no-op if already clean)
git add .gitignore README.md setup-branches.sh
if [[ -n $(git status --porcelain) ]]; then
  git commit -m "chore: apply .gitignore — untrack Design/, tests, build artefacts from main

main now contains architecture-level Swift source only.
Design files  → branch: design
Test targets  → branch: testing"
  echo "  ✓ Committed .gitignore cleanup to main"
else
  echo "  ✓ main already clean"
fi
echo ""

# ── 2. design branch ─────────────────────────────────────────────────────────
echo "── Step 2: Create \`design\` branch ──"
make_branch "design"

if ! git show-ref --verify --quiet "refs/heads/design" 2>/dev/null; then
  : # already handled in make_branch
fi

# Switch to design, force-add Design/ folder even though .gitignore excludes it
git checkout design
git add -f Design/
if [[ -n $(git status --porcelain) ]]; then
  git commit -m "design: add Design/ folder

Figma exports and HTML design reference files:
- ScanHonest.html           (full design spec, 1.25 MB)
- ScanHonest-Components.html (component library)
- ScanHonest-Icon.html
- screens.jsx               (all 10 screens)
- design-canvas.jsx
- ios-frame.jsx

Tracked on this branch only — kept off main to keep source repo lean."
  echo "  ✓ Design files committed to design branch"
else
  echo "  ✓ Design files already committed on design branch"
fi

git checkout main
echo ""

# ── 3. testing branch ────────────────────────────────────────────────────────
echo "── Step 3: Create \`testing\` branch ──"
make_branch "testing"

git checkout testing

# Force-add test dirs even though .gitignore excludes them
git add -f ScanHonestTests/
git add -f ScanHonestUITests/
if [[ -n $(git status --porcelain) ]]; then
  git commit -m "test: add unit and UI test targets

Unit tests (ScanHonestTests/):
  ChecksumIntegrityTests, FileNamingTests, FolderOperationsTests,
  PasswordProtectionTests, ScanLimitManagerTests, ScannedDocumentTests,
  StorageManagerTests, StoreKitManagerTests, SubscriptionAccessControlTests

UI tests (ScanHonestUITests/):
  DocumentDetailUITests, LibraryUITests, OnboardingUITests, PaywallUITests,
  ScanReviewUITests, SettingsUITests, ShareSheet10BUITests, UITestHelpers

Tracked on this branch only — kept off main to keep architecture source clean."
  echo "  ✓ Test files committed to testing branch"
else
  echo "  ✓ Test files already committed on testing branch"
fi

git checkout main
echo ""

# ── 4. Final summary ─────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    ✅ Setup Complete                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Local branches:"
git branch -v
echo ""
echo "Push to GitHub:"
echo ""
echo "  git push origin main design testing"
echo ""
echo "Branch contents:"
echo "  main    → Swift source only (architecture level)"
echo "  design  → Design/ folder (HTML/JSX design files)"
echo "  testing → ScanHonestTests/ + ScanHonestUITests/"
echo ""
