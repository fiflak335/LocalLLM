#!/bin/bash
# LocalLLM IPA Build Script
# Usage: ./build_ipa.sh [configuration] [export_method]
# Example: ./build_ipa.sh Release ad-hoc

set -e

PROJECT_NAME="LocalLLM"
SCHEME_NAME="LocalLLM"
CONFIGURATION="${1:-Release}"
EXPORT_METHOD="${2:-ad-hoc}"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/ipa"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

echo "🚀 Building $PROJECT_NAME ($CONFIGURATION)..."

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create ExportOptions.plist
cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>$EXPORT_METHOD</string>
    <key>teamID</key>
    <string>\${DEVELOPMENT_TEAM:-}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

# Resolve Swift Package dependencies
echo "📦 Resolving Swift Package dependencies..."
xcodebuild -resolvePackageDependencies \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION"

# Build and archive
echo "🔨 Archiving..."
xcodebuild archive \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="iPhone Distribution" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
    PROVISIONING_PROFILE_SPECIFIER="${PROVISIONING_PROFILE_SPECIFIER:-}"

# Export IPA
echo "📦 Exporting IPA..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

# Find the generated IPA
IPA_PATH=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)

if [ -z "$IPA_PATH" ]; then
    echo "❌ Error: IPA not found!"
    exit 1
fi

echo "✅ Build successful!"
echo "📱 IPA: $IPA_PATH"
echo "📏 Size: $(ls -lh "$IPA_PATH" | awk '{print $5}')"

# Copy to current directory for easy access
cp "$IPA_PATH" "./${PROJECT_NAME}.ipa"
echo "📋 Copied to ./${PROJECT_NAME}.ipa"

# Optional: Upload to TestFlight (requires App Store Connect API key)
if [ -n "$APP_STORE_CONNECT_API_KEY_ID" ] && [ -n "$APP_STORE_CONNECT_API_ISSUER_ID" ] && [ -n "$APP_STORE_CONNECT_API_KEY_PATH" ]; then
    echo "🚀 Uploading to TestFlight..."
    xcrun altool --upload-app \
        -f "$IPA_PATH" \
        -t ios \
        --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
        --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID" \
        --apiKeyPath "$APP_STORE_CONNECT_API_KEY_PATH"
fi