#!/bin/bash

# Script to generate Info.plist with NSAppTransportSecurity exceptions
# based on EXTERNAL_IP from .env file

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SRCROOT}"
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$SCRIPT_DIR"
fi
ENV_FILE="$PROJECT_DIR/Pointer/.env"
INFO_PLIST="$PROJECT_DIR/Info.plist"

echo "🔧 Generating Info.plist from .env configuration..."

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ Error: .env file not found at $ENV_FILE${NC}"
    echo "Please create a .env file with EXTERNAL_IP defined."
    exit 1
fi

# Read EXTERNAL_IP from .env
EXTERNAL_IP=$(grep "^EXTERNAL_IP=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]' | tr -d '"' | tr -d "'")

if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${RED}❌ Error: EXTERNAL_IP not found in .env file${NC}"
    echo "Please add EXTERNAL_IP=your.ip.address to your .env file"
    exit 1
fi

echo -e "${GREEN}✓ Found EXTERNAL_IP: $EXTERNAL_IP${NC}"

# Generate Info.plist with the IP from .env
cat > "$INFO_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>\$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>\$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>\$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>\$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>\$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>\$(CURRENT_PROJECT_VERSION)</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSExceptionDomains</key>
		<dict>
			<key>$EXTERNAL_IP</key>
			<dict>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
			</dict>
		</dict>
	</dict>
	<key>NSCameraUsageDescription</key>
	<string>Pointer needs camera access to stream video</string>
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>Pointer needs access to save captured object photos to your photo library</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Pointer needs access to save captured object photos to your photo library</string>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<true/>
	</dict>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
EOF

echo -e "${GREEN}✓ Info.plist generated successfully with exception for $EXTERNAL_IP${NC}"
echo "  Location: $INFO_PLIST"
