SWIFTC = swiftc
SWIFTFLAGS = -O -g
SOURCES = Sources/EarthViewer/Views/main.swift Sources/EarthViewer/Models/Assets.swift Sources/EarthViewer/Utils/SecurityUtils.swift

.PHONY: all clean run

all: build/Hello.app

run: all
	@open build/Hello.app

build/Hello: $(SOURCES)
	@echo "Creating directories..."
	@mkdir -p build
	@-pkill Hello 2>/dev/null || true
	@echo "Compiling Swift files..."
	@$(SWIFTC) $(SWIFTFLAGS) $(SOURCES) -o $@

build/Hello.app: build/Hello
	@echo "Creating app bundle..."
	@mkdir -p $@/Contents/MacOS
	@mkdir -p $@/Contents/Resources
	@cp Config/Info.plist $@/Contents/
	@cp Config/hello.entitlements $@/Contents/
	@cp build/Hello $@/Contents/MacOS/
	@cp -r Resources/Assets $@/Contents/Resources/
	@touch $@

clean:
	@echo "Cleaning..."
	@-pkill Hello 2>/dev/null || true
	@rm -rf build/
	@echo "Clean complete" 