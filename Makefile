# Variables
APP_NAME = Hello
APP_BUNDLE = build/$(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
MACOS_DIR = $(CONTENTS_DIR)/MacOS

# Source directories
SOURCES_DIR = Sources/EarthViewer
CONFIG_DIR = Config
ASSETS_DIR = Resources/Assets

# Source files
SWIFT_FILES = $(SOURCES_DIR)/Views/main.swift \
              $(SOURCES_DIR)/Utils/SecurityUtils.swift \
              $(SOURCES_DIR)/Models/Assets.swift

FRAMEWORKS = -framework Cocoa -framework SceneKit -framework CryptoKit
SWIFT_FLAGS = -I$(SOURCES_DIR)

# Earth texture variables
EARTH_IMAGE1 = $(ASSETS_DIR)/earth1.jpg
EARTH_IMAGE2 = $(ASSETS_DIR)/earth2.jpg
EARTH_IMAGE3 = $(ASSETS_DIR)/earth3.jpg
EARTH_DOWNLOAD1 = $(ASSETS_DIR)/downloads/earth_download1.jpg
EARTH_DOWNLOAD2 = $(ASSETS_DIR)/downloads/goes_east.jpg
EARTH_DOWNLOAD3 = $(ASSETS_DIR)/downloads/goes_west.jpg
EARTH_COMPOSITE = $(ASSETS_DIR)/cloud_composite.jpg

# Image sources
# Blue Marble (Base image)
EARTH_URL1 = https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57730/land_ocean_ice_2048.jpg
# GOES-East latest full disk image
EARTH_URL2 = https://cdn.star.nesdis.noaa.gov/GOES16/ABI/FD/GEOCOLOR/latest.jpg
# GOES-West latest full disk image
EARTH_URL3 = https://cdn.star.nesdis.noaa.gov/GOES17/ABI/FD/GEOCOLOR/latest.jpg

# Check for ImageMagick
IMAGEMAGICK := $(shell command -v convert 2> /dev/null)

.PHONY: all clean run monitor

all: $(APP_BUNDLE)

# Create the app bundle and copy all resources
$(APP_BUNDLE): build/$(APP_NAME) $(EARTH_IMAGE1) $(EARTH_IMAGE2) $(EARTH_IMAGE3) | build_dirs
	@echo "Creating app bundle..."
	@cp build/$(APP_NAME) "$(MACOS_DIR)/"
	@cp $(CONFIG_DIR)/Info.plist "$(CONTENTS_DIR)/"
	@cp $(EARTH_IMAGE1) "$(RESOURCES_DIR)/earth1.jpg"
	@cp $(EARTH_IMAGE2) "$(RESOURCES_DIR)/earth2.jpg"
	@cp $(EARTH_IMAGE3) "$(RESOURCES_DIR)/earth3.jpg"
	@cp $(CONFIG_DIR)/hello.entitlements "$(CONTENTS_DIR)/"
	@echo "Build complete: $(APP_BUNDLE)"

# Compile the Swift files
build/$(APP_NAME): $(SWIFT_FILES) | build_dirs
	@echo "Compiling Swift files..."
	@swiftc -o $@ $(SWIFT_FILES) $(FRAMEWORKS) $(SWIFT_FLAGS)

# Create necessary directories
build_dirs:
	@echo "Creating directories..."
	@mkdir -p build
	@mkdir -p "$(MACOS_DIR)"
	@mkdir -p "$(RESOURCES_DIR)"
	@mkdir -p "$(ASSETS_DIR)/downloads"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf build
	@rm -rf *.o
	@rm -rf *.dSYM
	@rm -rf $(APP_NAME).app
	@rm -rf "$(ASSETS_DIR)/downloads"
	@echo "Clean complete"

# Run the application
run: $(APP_BUNDLE)
	@echo "Running application..."
	@open $(APP_BUNDLE)

# Monitor application logs
monitor:
	@echo "Monitoring Hello.app logs..."
	@log stream --predicate 'process == "Hello"' --style compact

# Add a run-and-monitor target that builds, runs, and monitors
run-and-monitor: $(APP_BUNDLE)
	@echo "Running and monitoring application..."
	@open $(APP_BUNDLE) & \
	log stream --predicate 'process == "Hello"' --style compact

# Download and process Earth textures
$(EARTH_IMAGE1): $(EARTH_DOWNLOAD1)
	@echo "Processing Earth texture 1..."
	@sips -s format jpeg -s formatOptions 100 $(EARTH_DOWNLOAD1) --out $(EARTH_IMAGE1)

$(EARTH_IMAGE2): $(EARTH_DOWNLOAD2) $(EARTH_IMAGE1)
	@echo "Processing GOES-East texture..."
	@echo "  $(EARTH_DOWNLOAD2)"
	@echo "  $@"
	@magick $(EARTH_DOWNLOAD2) \
		-virtual-pixel Transparent \
		-alpha set \
		-distort Perspective '0,0,768,0  5424,0,1280,0  5424,5424,1280,2048  0,5424,768,2048' \
		-resize 2048x2048 \
		\( $(EARTH_IMAGE1) -resize 2048x2048 \) \
		-compose Over -composite \
		$@

$(EARTH_IMAGE3): $(EARTH_DOWNLOAD3) $(EARTH_IMAGE1)
	@echo "Processing GOES-West texture..."
	@echo "  $(EARTH_DOWNLOAD3)"
	@echo "  $@"
	@magick $(EARTH_DOWNLOAD3) \
		-virtual-pixel Transparent \
		-alpha set \
		-distort Perspective '0,0,512,0  2048,0,1024,0  2048,2048,1024,2048  0,2048,512,2048' \
		-resize 2048x2048 \
		\( $(EARTH_IMAGE1) -resize 2048x2048 \) \
		-compose Over -composite \
		$@

# Create cloud cover composite
$(EARTH_COMPOSITE): $(EARTH_DOWNLOAD2) $(EARTH_DOWNLOAD3)
	@echo "Creating cloud cover composite..."
	# Process GOES-East
	@convert $(EARTH_DOWNLOAD2) -resize 2048x1024! \
		-gravity center -extent 2048x1024 \
		-distort Perspective '0,0 0,0  2048,0 2048,0  2048,1024 1024,1024  0,1024 0,1024' \
		$(ASSETS_DIR)/downloads/goes_east_warped.png
	# Process GOES-West
	@convert $(EARTH_DOWNLOAD3) -resize 2048x1024! \
		-gravity center -extent 2048x1024 \
		-distort Perspective '0,0 1024,0  2048,0 2048,0  2048,1024 2048,1024  0,1024 1024,1024' \
		$(ASSETS_DIR)/downloads/goes_west_warped.png
	# Combine images
	@convert $(ASSETS_DIR)/downloads/goes_east_warped.png $(ASSETS_DIR)/downloads/goes_west_warped.png \
		-compose blend -composite \
		-brightness-contrast 10x20 \
		$(EARTH_COMPOSITE)

# Download Earth textures
$(EARTH_DOWNLOAD1): | build_dirs
	@echo "Downloading base Earth texture..."
	@curl -f -L -o $(EARTH_DOWNLOAD1) $(EARTH_URL1)

$(EARTH_DOWNLOAD2): | build_dirs
	@echo "Downloading GOES-East image..."
	@curl -f -L -o $(EARTH_DOWNLOAD2) $(EARTH_URL2)

$(EARTH_DOWNLOAD3): | build_dirs
	@echo "Downloading GOES-West image..."
	@curl -f -L -o $(EARTH_DOWNLOAD3) $(EARTH_URL3) 