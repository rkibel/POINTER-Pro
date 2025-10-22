# POINTER-Pro

**P**ersistent **O**bject-anchored **I**nteractions and **T**agging for **E**nriched **R**eality

iOS application for object-centric virtual overlays using real-time pose estimation and LiveKit streaming.

## Features

- ✅ Interactive home page with navigation
- ✅ Real-time camera preview with pose estimation region indicator
- ✅ Stream to LiveKit server
- ✅ Back camera capture at 720p/30fps
- ✅ Visual overlay showing active estimation region
- ✅ Connection status monitoring
- ✅ Environment-based configuration
- ✅ Object scanning with multi-angle photo capture
- ✅ Export photos to Photos app or share via iOS share sheet
- ✅ Independent camera sessions for scanning and inference

## Requirements

- iOS 14.0+
- Xcode 14.0+
- Swift 5.5+
- LiveKit Server (self-hosted or cloud)

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/rkibel/POINTER-Pro.git
cd POINTER-Pro
```

### 2. Configure Environment

Copy the example environment file and fill in your LiveKit server details:

```bash
cp .env.example .env
```

Edit `.env` with your LiveKit server information:

```bash
# LiveKit Server Configuration
LIVEKIT_URL=ws://your-server-ip:7880
LIVEKIT_TOKEN=your_generated_token_here
LIVEKIT_ROOM=live
```

**Important:** Never commit your `.env` file! It contains sensitive credentials.

### 3. Set Up LiveKit Server

Follow the comprehensive guide in [`livekit-server-setup.md`](./livekit-server-setup.md) to:
- Install LiveKit on your server
- Configure firewall rules
- Generate access tokens

### 4. Open and Build

1. Open `Pointer/Pointer.xcodeproj` in Xcode
2. Select your development team in signing settings
3. Build and run on a physical device (camera not available in simulator)

## Usage

### Scanning Objects

1. Launch the app to see the POINTER home page
2. Tap **Scan Objects** to start the object scanning interface
3. Grant camera permissions when prompted
4. Position your object within the scan guide (center square)
5. Tap the **capture button** (white circle) to take photos from different angles
6. Take **5 photos** total - the app will guide you with a counter
7. Review captured photos in the thumbnail gallery at the bottom
8. Tap thumbnails to view full-screen images
9. Use the **trash button** to delete individual photos or **Clear** to start over
10. Once 5/5 photos are captured, tap **Export** to:
    - **Save to Photos** - Save all 5 photos to your Photos library
    - **Share** - Use iOS share sheet to export via AirDrop, Files, iCloud, etc.

### Live Inference

1. From the home page, tap **Inference** to start the streaming interface
2. The camera preview will appear with visual indicators showing the pose estimation region
3. Press the **Play** button to start streaming to LiveKit server
4. Press **Stop** to end the stream
5. Monitor connection status indicator at the top of the screen

**Note:** Scan Objects and Inference use independent camera sessions - switching between them properly allocates/deallocates resources.

## Project Structure

```
Pointer/
├── PointerApp.swift            # App entry point
├── HomeView.swift              # Main landing page with navigation
├── StreamingView.swift         # Live inference UI with streaming
├── ScanObjectsView.swift       # Object scanning interface
├── CameraPreviewView.swift     # LiveKit camera preview view
├── ScanCameraPreviewView.swift # AVFoundation camera preview view
├── WebRTCManager.swift         # Streaming logic and LiveKit integration
├── ScanCameraManager.swift     # Object scanning camera manager
└── Config.swift                # Environment configuration loader
```

## Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `LIVEKIT_URL` | WebSocket URL to LiveKit server | `ws://34.16.147.65:7880` |
| `LIVEKIT_TOKEN` | JWT access token | `eyJhbGci...` |
| `LIVEKIT_ROOM` | Room name (optional) | `live` |

### Camera Settings

Default camera configuration in `WebRTCManager.swift`:
- **Position:** Back camera
- **Resolution:** 1280x720 (720p)
- **FPS:** 30

To modify, edit the `LocalVideoTrackOptions` in `startCameraCapture()`.

## Generating Tokens

### Quick Method (Testing)

Use the included script:

```bash
./generate-token.sh live ios-camera 24
```

This generates a token valid for 24 hours for room "live" with identity "ios-camera".

### Using LiveKit CLI

```bash
livekit-cli create-token \
  --api-key YOUR_API_KEY \
  --api-secret YOUR_API_SECRET \
  --join --room live \
  --identity ios-camera \
  --valid-for 24h
```

### Production

For production apps, generate tokens server-side using LiveKit's token generation libraries. Never hardcode API secrets in your app.

## Viewing the Stream

### Option 1: LiveKit Meet

1. Visit https://meet.livekit.io/custom
2. Enter your LiveKit server URL
3. Generate a viewer token (with same room name)
4. Join the room

### Option 2: Build a Viewer App

Create another iOS or web app that subscribes to the same room using LiveKit SDK.

## Troubleshooting

### Camera Preview Not Showing

- Ensure camera permissions are granted
- Check that you're running on a physical device (not simulator)
- Review logs in Xcode console

### Connection Failed

- Verify `.env` file exists and contains correct values
- Check LiveKit server is running: `curl http://YOUR_IP:7880/`
- Ensure firewall allows ports 7880 (TCP) and 50000-60000 (UDP)
- Validate token hasn't expired

### Token Errors

- Regenerate token with correct API keys
- Verify room name matches between app and token
- Check token expiration time

### No Video on Viewer Side

- Ensure UDP ports 50000-60000 are open on server
- Check `external_ip` setting in LiveKit config
- Verify token has `canPublish: true` permission

## Development

### Dependencies

The project uses Swift Package Manager with the following packages:
- **LiveKit Swift SDK** (2.8.1): Real-time video streaming

### Building

```bash
cd Pointer
xcodebuild -scheme Pointer -destination 'platform=iOS,name=YOUR_DEVICE'
```

### Running Tests

Currently no automated tests. Manual testing required.

## Security

⚠️ **Security Best Practices:**

1. **Never commit `.env` file** - It's gitignored for your safety
2. **Use strong API keys** - Change default "devkey/secret" in production
3. **Generate tokens server-side** - Don't hardcode secrets in app
4. **Use HTTPS/WSS** - Enable TLS for production deployments
5. **Short-lived tokens** - Generate tokens with short expiration times
6. **Validate permissions** - Ensure tokens have minimal required permissions

## License

[Your License Here]

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Support

For LiveKit server setup issues, see [`livekit-server-setup.md`](./livekit-server-setup.md).

For app-specific issues, open an issue on GitHub.

## Credits

Built with:
- [LiveKit](https://livekit.io/) - Real-time video infrastructure
- SwiftUI - Modern iOS UI framework

---

Made with ❤️ for real-time streaming
