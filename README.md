# Hello World Globe

A modern take on the classic "Hello World" program, displaying a 3D Earth globe with satellite imagery overlays.

## GitHub Setup

1. Configure Git (replace with your information):
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   ```

2. Create a new repository on GitHub:
   - Go to https://github.com/new
   - Name: `earth-viewer`
   - Description: "A modern Hello World with 3D Earth visualization"
   - Choose "Public" or "Private"
   - Don't initialize with README (we already have one)

3. Create a Personal Access Token (PAT):
   - Go to GitHub.com → Profile picture → Settings
   - Scroll to "Developer settings" → "Personal access tokens" → "Tokens (classic)"
   - Click "Generate new token" → "Generate new token (classic)"
   - Name: "earth-viewer-access"
   - Set expiration as needed
   - Select scopes: check `repo` for repository access
   - Click "Generate token" and copy it immediately

4. Link and push to GitHub (replace `YOUR-TOKEN`):
   ```bash
   git remote add origin https://YOUR-TOKEN@github.com/YOUR-USERNAME/earth-viewer.git
   git branch -M main
   git push -u origin main
   ```

## Features

- Interactive 3D Earth globe with smooth counter-clockwise rotation
- Base layer using NASA's Blue Marble imagery
- Optional real-time satellite overlays:
  - GOES-East satellite imagery (toggle with button)
  - GOES-West satellite imagery (toggle with button)
  - Overlays blend seamlessly with the base layer
  - Last update time display for each satellite feed
- Dynamic globe sizing that scales with window size
- Bounce mode that makes the globe bounce around the window:
  - Click the globe to change its bounce direction
  - Direction changes are significant (90-270 degrees)
  - Maintains constant rotation while bouncing
- Auto-updating satellite imagery every 10 minutes
- Responsive window sizing with minimum dimensions (480x400)
- Persistent state for overlay selections and bounce mode
- Enhanced security features:
  - Certificate pinning for satellite image servers
  - Domain-specific transport security settings
  - Secure logging with rotation and size limits
  - Sandboxed application environment
  - Resource validation and integrity checks

## Controls

- **GOES-East Button**: Toggle the GOES-East satellite overlay
  - Uses emission mapping for clear visibility
  - Updates every 10 minutes with latest imagery
- **GOES-West Button**: Toggle the GOES-West satellite overlay
  - Uses specular mapping for distinct appearance
  - Updates every 10 minutes with latest imagery
- **Bounce! Button**: Toggle bounce mode
  - When active, the globe bounces around the window
  - Click the globe to change its direction
  - When inactive, the globe stays centered

## Building

1. Ensure you have macOS 10.15 or later
2. Run `make` to compile the application
3. Run `make clean` to remove built files
4. The application will be built as `build/Hello.app`
5. Optional: Use `make run-and-monitor` to run with logging

## Project Structure

```
earth-viewer/
├── Sources/
│   └── EarthViewer/
│       ├── Views/
│       │   └── main.swift
│       ├── Models/
│       │   └── Assets.swift
│       └── Utils/
│           └── SecurityUtils.swift
├── Resources/
│   └── Assets/
├── Config/
│   ├── Makefile
│   ├── Info.plist
│   └── hello.entitlements
└── README.md
```

## Technical Details

- Built with Swift and SceneKit for 3D rendering
- Uses NASA Blue Marble imagery for base texture
- Integrates real-time GOES satellite imagery from NOAA
- Implements comprehensive security features:
  - SSL/TLS certificate pinning with backup certificates
  - Domain-specific transport security exceptions
  - File size validation (50MB limit)
  - Checksum verification for downloads
  - Secure logging with rotation (10MB per file, 5 files max)
  - Exponential backoff for failed requests
  - Atomic file operations
  - Temporary file cleanup
  - Debug/Production logging modes
- Supports window resizing with dynamic content scaling
- Enhanced click detection using both gesture recognizer and direct mouse events
- Smooth rotation using custom SCNAction for consistent movement
- Material blending for clear overlay visibility

## Security Features

### Network Security
- Certificate pinning for NOAA and NASA servers
- HTTPS-only connections with CT verification
- Domain-specific security policies
- Custom User-Agent header
- Exponential backoff for failed requests

### Resource Validation
- File size limits (50MB max)
- SHA-256 checksum verification
- Atomic file operations
- Temporary file cleanup
- Secure download handling

### Application Security
- Sandboxed environment
- Limited system access
- Secure preference storage
- Debug/Production logging modes
- Log rotation and management

### Error Handling
- Comprehensive error tracking
- Secure logging system
- Non-sensitive information logging
- Automatic log rotation
- Detailed debug output in development

## Development Mode

The application includes a debug mode that provides:
- Enhanced logging output
- Window always-on-top functionality
- Detailed click and interaction logging
- Extended error information

To disable debug mode for production:
1. Set `DEBUG_MODE = false` in AppDelegate
2. Rebuild the application

## Data Sources

- Base Earth texture: NASA Blue Marble (https://visibleearth.nasa.gov/)
- GOES-East: NOAA GOES-16 satellite
- GOES-West: NOAA GOES-17 satellite
