# Hello World Globe Application

A macOS application that displays a rotating Earth globe with "Hello World!" text.

## Project Structure

hello/
├── main.swift         # Main application code with GlobeView and AppDelegate
├── Assets.swift       # Asset management for Earth textures
├── Info.plist        # Application configuration
├── Makefile          # Build automation
└── Resources/        # Generated during build
    ├── earth1.jpg    # NASA Blue Marble base image
    ├── earth2.jpg    # GOES-East satellite image
    └── earth3.jpg    # GOES-West satellite image

## Features

- Interactive Earth view with three texture options:
  - NASA Blue Marble (land, ocean, and ice caps)
  - GOES-East satellite view (Americas and Atlantic)
  - GOES-West satellite view (Pacific and Asia)
- Easy texture switching with highlighted buttons
- Persistent texture selection across app launches
- Smooth globe rotation
- Responsive window sizing (200x150 to full screen)
- White "Hello World!" text that scales with window size
- Matte finish on the globe with realistic lighting
- Menu bar with Quit option
- Proper full-screen support

## Build Instructions

1. Run `make` to:
   - Download NASA Blue Marble image
   - Download latest GOES satellite images
   - Process images for texture use
   - Compile the application
   - Create the app bundle

2. Run `make clean` to remove:
   - Built application
   - Downloaded resources
   - Generated files

## Technical Details

- Uses SceneKit for 3D rendering
- Globe size: Adaptive to window size
- Initial window size: 800x600
- Minimum window size: 200x150
- Maximum window size: Full screen
- Texture sources:
  - Blue Marble: NASA Earth Observatory
  - GOES-East: NOAA GOES-16 satellite
  - GOES-West: NOAA GOES-17 satellite

## Data Sources

- NASA Blue Marble: Base Earth texture without clouds
- GOES-East: Real-time view of Western Hemisphere
- GOES-West: Real-time view of Eastern Hemisphere

## Controls

- Three buttons at bottom of window:
  - "Blue Marble": Classic NASA Earth view
  - "GOES-East": Americas and Atlantic view
  - "GOES-West": Pacific and Asia view
- Selected texture is highlighted
- Selection persists between app launches

## Key Components

### GlobeView
- 3D Earth rendering
- Texture management
- Button controls
- State persistence

### AppDelegate
- Window management
- Menu setup
- Text scaling
- Application lifecycle

## Dependencies

- macOS 10.15 or later
- Cocoa framework
- SceneKit framework

## Notes

The application maintains proper appearance during:
- Window resizing
- Full-screen transitions
- Menu bar visibility changes
- Texture switching
