#!/bin/bash
set -e

echo "=========================================="
echo "🧪 Running Horizon CI Pipeline Locally"
echo "=========================================="

# 1. Clean previous artifacts
echo "🧹 Cleaning previous build and test artifacts..."
rm -rf TestResults.xcresult build dmg_root Horizon.dmg test_build.log coverage.json coverage_report.txt pr_comment.md test_report.md

# 2. Check Xcode Version
echo "🔍 Checking Xcode Version..."
xcodebuild -version

# 3. Run Tests with Code Coverage
echo "🧪 Step 1: Running Tests with Code Coverage..."
set -o pipefail
xcodebuild test \
  -project Horizon.xcodeproj \
  -scheme Horizon \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  | tee test_build.log

# 4. Extract Code Coverage
echo "📊 Step 2: Extracting Code Coverage..."
if [ -d "TestResults.xcresult" ]; then
  xcrun xccov view --report --json TestResults.xcresult > coverage.json 2>/dev/null || true
  xcrun xccov view --report TestResults.xcresult > coverage_report.txt 2>/dev/null || true
fi

# 5. Build Release App
echo "🔨 Step 3: Building Release Application..."
xcodebuild build \
  -project Horizon.xcodeproj \
  -scheme Horizon \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# 6. Package DMG
echo "📦 Step 4: Packaging Horizon DMG..."
mkdir -p dmg_root
cp -R build/Build/Products/Release/Horizon.app dmg_root/
ln -s /Applications dmg_root/Applications
hdiutil create -volname "Horizon" -srcfolder dmg_root -ov -format UDZO Horizon.dmg

# 7. Generate CI Summary Report & PR Comment
echo "📝 Step 5: Generating Test & Coverage Reports..."
export GITHUB_SHA=$(git rev-parse HEAD 2>/dev/null || echo "local-test")
export GITHUB_REF_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "local")
export GITHUB_RUN_ID="local-run"
export GITHUB_REPOSITORY="Zephyrus02/Horizon"
python3 .github/scripts/generate_ci_report.py test_build.log coverage.json coverage_report.txt Horizon.dmg

echo ""
echo "=========================================="
echo "✅ Local CI Pipeline Run Complete!"
echo "=========================================="
echo "Artifacts generated:"
echo " - DMG:           Horizon.dmg ($(ls -lh Horizon.dmg | awk '{print $5}'))"
echo " - Test Results:  TestResults.xcresult"
echo " - Test Report:   test_report.md"
echo " - PR Comment:    pr_comment.md"
echo "=========================================="
echo ""
echo "PR Comment Preview:"
echo "------------------------------------------"
cat pr_comment.md
echo "------------------------------------------"

