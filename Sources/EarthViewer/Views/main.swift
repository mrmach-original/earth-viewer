import Cocoa
import SceneKit
import CoreGraphics
import os.log

class GlobeView: NSView {
    private var sceneView: SCNView!
    private var sphereNode: SCNNode!
    private var textureButtons: [NSButton] = []
    private var updateLabels: [NSTextField] = []
    private var updateTimer: Timer?
    
    // Track overlay states
    private var goesEastEnabled = false {
        didSet {
            UserDefaults.standard.set(goesEastEnabled, forKey: "goesEastEnabled")
            updateTextures()
        }
    }
    private var goesWestEnabled = false {
        didSet {
            UserDefaults.standard.set(goesWestEnabled, forKey: "goesWestEnabled")
            updateTextures()
        }
    }
    
    // Add last update time tracking
    private var lastUpdateTimes: [String: Date] = [:]
    
    // Add new properties
    private var bounceEnabled = UserDefaults.standard.bool(forKey: "bounceEnabled") {
        didSet {
            UserDefaults.standard.set(bounceEnabled, forKey: "bounceEnabled")
        }
    }
    private var velocity = SCNVector3(x: 4, y: 3, z: 0)
    private var bounceTimer: Timer?
    private var bounceButton: NSButton?  // Store reference to bounce button
    private let sphereRadius: Float = 1.0
    private var boundsX: Float = 3.5
    private var boundsY: Float = 2.5
    
    private let log = OSLog(subsystem: "Hello", category: "default")
    private var isDebugMode: Bool {
        return (NSApp.delegate as? AppDelegate)?.DEBUG_MODE ?? false
    }
    
    deinit {
        updateTimer?.invalidate()
        bounceTimer?.invalidate()
    }
    
    // Define texture types
    enum EarthTexture: String {
        case blueMarble = "Blue Marble"
        case goesEast = "GOES-East"
        case goesWest = "GOES-West"
        
        var filename: String {
            switch self {
            case .blueMarble: return "earth1.jpg"
            case .goesEast: return "earth2.jpg"
            case .goesWest: return "earth3.jpg"
            }
        }
    }
    
    private func startUpdateTimer() {
        // Update every 10 minutes (600 seconds)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.refreshTextures()
        }
    }
    
    private func refreshTextures() {
        // Only refresh GOES images
        if goesEastEnabled || goesWestEnabled {
            updateTextures()
            if goesEastEnabled {
                updateLastUpdateTime(for: "GOES-East")
            }
            if goesWestEnabled {
                updateLastUpdateTime(for: "GOES-West")
            }
        }
    }
    
    private func updateLastUpdateTime(for textureName: String) {
        lastUpdateTimes[textureName] = Date()
        updateTimeLabels()
    }
    
    private func updateTimeLabels() {
        let goesLabels = ["GOES-East", "GOES-West"]
        for (index, name) in goesLabels.enumerated() {
            let baseText = Assets.metadata[name == "GOES-East" ? .goesEast : .goesWest]?.updateFrequency ?? ""
            if let lastUpdate = lastUpdateTimes[name] {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timeString = formatter.string(from: lastUpdate)
                updateLabels[index].stringValue = "\(baseText)\nLast update: \(timeString)"
            } else {
                updateLabels[index].stringValue = baseText
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        // Set default value for first launch
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            UserDefaults.standard.set(true, forKey: "bounceEnabled")
            bounceEnabled = true
        }
        
        // Load initial states before super.init
        goesEastEnabled = UserDefaults.standard.bool(forKey: "goesEastEnabled")
        goesWestEnabled = UserDefaults.standard.bool(forKey: "goesWestEnabled")
        
        super.init(frame: frameRect)
        
        // Log startup
        os_log("EarthViewer initializing with frame: %{public}@", log: log, type: .info, String(describing: frameRect))
        
        setupScene()
        
        // Start update timer for GOES images
        startUpdateTimer()
        
        // Start in appropriate mode based on saved state
        if bounceEnabled {
            startBouncing()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupScene() {
        // Create SceneView
        sceneView = SCNView(frame: bounds)
        sceneView.autoresizingMask = [.width, .height]
        sceneView.backgroundColor = .clear
        addSubview(sceneView)
        
        // Enable click handling - both gesture recognizer and direct mouse events
        sceneView.allowsCameraControl = false
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        clickGesture.buttonMask = 0x1   // Left mouse button
        sceneView.addGestureRecognizer(clickGesture)
        
        // Create Scene
        let scene = SCNScene()
        sceneView.scene = scene
        
        // Create single globe
        let sphere = SCNSphere(radius: 1.0)
        sphere.segmentCount = 96
        
        sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)
        
        // Add rotation animation (2 revolutions per minute = 30 seconds per revolution)
        startRotation()
        
        // Camera setup with name for easy reference
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 8.0)
        scene.rootNode.addChildNode(cameraNode)
        
        updateBoundsForCurrentSize()  // Set initial bounds
        
        // Lighting
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = NSColor(white: 0.3, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.position = SCNVector3(x: 5, y: 5, z: 5)
        scene.rootNode.addChildNode(directionalLight)
        
        // Create button container that stays at bottom and spans window width
        let buttonContainerHeight: CGFloat = 150
        let buttonContainer = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: buttonContainerHeight
        ))
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonContainer)
        
        // Button dimensions
        let buttonHeight: CGFloat = 30
        let buttonSpacing: CGFloat = 20
        let textureButtonWidth: CGFloat = 120
        
        // Create a stack view for GOES buttons
        let buttonStackView = NSStackView()
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.orientation = .horizontal
        buttonStackView.spacing = buttonSpacing
        buttonStackView.distribution = .fillEqually
        buttonContainer.addSubview(buttonStackView)
        
        // Create GOES buttons
        let goesButtons = [("GOES-East", goesEastEnabled), ("GOES-West", goesWestEnabled)]
        for (index, (title, isEnabled)) in goesButtons.enumerated() {
            let button = NSButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.title = title
            button.bezelStyle = .regularSquare
            button.setButtonType(.pushOnPushOff)
            button.state = isEnabled ? .on : .off  // Set initial state based on loaded preferences
            button.target = self
            button.action = #selector(goesButtonClicked(_:))
            button.tag = index
            buttonStackView.addArrangedSubview(button)
            textureButtons.append(button)
            
            // Set button size constraints
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: textureButtonWidth),
                button.heightAnchor.constraint(equalToConstant: buttonHeight)
            ])
            
            // Add update label below the button
            let label = NSTextField()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.stringValue = Assets.metadata[title == "GOES-East" ? .goesEast : .goesWest]?.updateFrequency ?? ""
            label.alignment = .center
            label.isBezeled = false
            label.isEditable = false
            label.drawsBackground = false
            label.textColor = .gray
            label.font = NSFont.systemFont(ofSize: 10)
            label.cell?.wraps = true
            label.cell?.truncatesLastVisibleLine = false
            buttonContainer.addSubview(label)
            updateLabels.append(label)
            
            // Position label relative to its button
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 5),
                label.widthAnchor.constraint(equalTo: button.widthAnchor),
                label.heightAnchor.constraint(equalToConstant: 30)
            ])
        }
        
        // Add Bounce button with toggle behavior
        let bounceButton = NSButton()
        bounceButton.translatesAutoresizingMaskIntoConstraints = false
        bounceButton.title = "Bounce!"
        bounceButton.bezelStyle = .rounded
        bounceButton.setButtonType(.pushOnPushOff)  // Change to push on/off type
        bounceButton.target = self
        bounceButton.action = #selector(bounceButtonClicked(_:))
        bounceButton.state = bounceEnabled ? .on : .off
        buttonContainer.addSubview(bounceButton)
        self.bounceButton = bounceButton
        
        // Layout constraints for the container and buttons
        NSLayoutConstraint.activate([
            buttonContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonContainer.heightAnchor.constraint(equalToConstant: buttonContainerHeight),
            
            // Center the button stack
            buttonStackView.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            buttonStackView.topAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: 20),
            
            // Position bounce button
            bounceButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            bounceButton.topAnchor.constraint(equalTo: updateLabels[0].bottomAnchor, constant: 20),
            bounceButton.widthAnchor.constraint(equalToConstant: 100),
            bounceButton.heightAnchor.constraint(equalToConstant: buttonHeight)
        ])
        
        // Remove duplicate state loading
        updateTextures()  // Just update textures based on already loaded state
    }
    
    @objc private func goesButtonClicked(_ sender: NSButton) {
        if sender.tag == 0 {
            goesEastEnabled.toggle()
        } else {
            goesWestEnabled.toggle()
        }
        sender.state = sender.tag == 0 ? (goesEastEnabled ? .on : .off) : (goesWestEnabled ? .on : .off)
    }
    
    @objc private func bounceButtonClicked(_ sender: NSButton) {
        bounceEnabled.toggle()
        sender.state = bounceEnabled ? .on : .off
        
        if bounceEnabled {
            startBouncing()
        } else {
            stopBouncing()
        }
    }
    
    private func startRotation() {
        // Remove any existing rotation action first
        sphereNode.removeAction(forKey: "rotation")
        
        // Create a smooth, continuous rotation
        let rotationDuration: TimeInterval = 30.0  // 30 seconds per revolution
        let rotation = SCNAction.repeatForever(
            SCNAction.customAction(duration: rotationDuration) { node, elapsedTime in
                let angle = CGFloat(-2.0 * Double.pi * (elapsedTime / rotationDuration))
                node.eulerAngles.y = angle
            }
        )
        
        // Run the rotation with a unique key
        sphereNode.runAction(rotation, forKey: "rotation")
    }
    
    private func startBouncing() {
        // Keep the rotation going during bounce
        // Don't remove the rotation action
        
        // Start bounce timer
        bounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateBouncePosition()
        }
    }
    
    private func stopBouncing() {
        // Stop bounce timer
        bounceTimer?.invalidate()
        bounceTimer = nil
        
        // No need to restart rotation since it was never stopped
    }
    
    private func updateBouncePosition() {
        let currentPosition = sphereNode.presentation.position
        var newPosition = currentPosition
        
        // Update position
        newPosition.x += velocity.x
        newPosition.y += velocity.y
        
        // Check x bounds
        if Float(abs(newPosition.x)) > boundsX {
            velocity.x *= -1
            newPosition.x = newPosition.x > 0 ? CGFloat(boundsX) : CGFloat(-boundsX)
        }
        
        // Check y bounds
        if Float(abs(newPosition.y)) > boundsY {
            velocity.y *= -1
            newPosition.y = newPosition.y > 0 ? CGFloat(boundsY) : CGFloat(-boundsY)
        }
        
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.0
        sphereNode.position = newPosition
        SCNTransaction.commit()
    }
    
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updateBoundsForCurrentSize()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateBoundsForCurrentSize()
    }
    
    private func updateBoundsForCurrentSize() {
        // Double the previous scale factor (was height/400.0)
        let scaleFactor = CGFloat(bounds.height) / 200.0
        sphereNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        
        // Calculate the scaled radius of the globe
        let scaledRadius = sphereRadius * Float(scaleFactor)
        
        // Set bounds to 1/40th of window dimensions minus the scaled radius
        boundsX = Float(bounds.width / 40) - scaledRadius
        boundsY = Float(bounds.height / 40) - scaledRadius
        
        // Calculate velocity for slower, more varied movement
        let diagonal = sqrt(pow(bounds.width, 2) + pow(bounds.height, 2))
        let speedMultiplier = (diagonal / (3.0 * 60.0)) * 0.05  // Reduced speed by half
        
        // Use a random angle between 30 and 60 degrees for more varied movement
        let randomAngle = CGFloat.random(in: CGFloat.pi/6...CGFloat.pi/3)
        velocity = SCNVector3(
            x: CGFloat(cos(randomAngle) * speedMultiplier),
            y: CGFloat(sin(randomAngle) * speedMultiplier),
            z: 0
        )
        
        // If globe is outside new bounds, move it inside
        if abs(sphereNode.position.x) > CGFloat(boundsX) {
            sphereNode.position.x = sphereNode.position.x > 0 ? CGFloat(boundsX) : CGFloat(-boundsX)
        }
        if abs(sphereNode.position.y) > CGFloat(boundsY) {
            sphereNode.position.y = sphereNode.position.y > 0 ? CGFloat(boundsY) : CGFloat(-boundsY)
        }
        
        // Update camera position based on window size
        if let cameraNode = sceneView.scene?.rootNode.childNode(withName: "camera", recursively: false) {
            let distanceFactor = CGFloat(bounds.height) / 200.0  // Using full window height
            cameraNode.position = SCNVector3(0, 0, 8.0 * distanceFactor)
        }
    }
    
    // Update texture handling
    private func updateTextures() {
        // Always start with Blue Marble
        if let baseImage = Assets.earthTexture(for: .blueMarble) {
            let material = SCNMaterial()
            material.diffuse.contents = baseImage
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.isDoubleSided = true
            
            // Apply overlays if enabled
            if goesEastEnabled {
                if let eastImage = Assets.earthTexture(for: .goesEast) {
                    // Use emission like GOES-West but with different parameters
                    material.emission.contents = eastImage
                    material.emission.intensity = 0.8  // Slightly higher intensity
                    material.emission.wrapS = .repeat
                    material.emission.wrapT = .repeat
                }
            }
            
            if goesWestEnabled {
                if let westImage = Assets.earthTexture(for: .goesWest) {
                    material.specular.contents = westImage  // Use specular for GOES-West
                    material.specular.intensity = 0.7
                    material.specular.wrapS = .repeat
                    material.specular.wrapT = .repeat
                }
            }
            
            sphereNode.geometry?.materials = [material]
        }
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        
        // Convert the event location to view coordinates
        let point = sceneView.convert(event.locationInWindow, from: nil)
        
        // Log the raw mouse click with appropriate level
        os_log("Raw mouse click at %{public}@", log: log, type: isDebugMode ? .fault : .info, String(describing: point))
        
        // Process the click
        processClick(at: point)
    }
    
    private func processClick(at point: CGPoint) {
        // Convert globe position to view coordinates
        let globeViewPos = sceneView.projectPoint(sphereNode.presentation.position)
        let globeCenter = CGPoint(x: CGFloat(globeViewPos.x), y: CGFloat(globeViewPos.y))
        
        // Log with appropriate level
        os_log("Globe center at %{public}@", log: log, type: isDebugMode ? .fault : .debug, String(describing: globeCenter))
        
        // Calculate distance from click to globe center
        let distance = sqrt(pow(point.x - globeCenter.x, 2) + pow(point.y - globeCenter.y, 2))
        
        // Use a more generous hit radius (half the view size)
        let hitRadius = min(sceneView.bounds.width, sceneView.bounds.height) / 2
        
        os_log("Click distance from center: %f, Hit radius: %f", log: log, type: isDebugMode ? .fault : .debug, distance, hitRadius)
        
        if distance <= hitRadius {
            os_log("GLOBE HIT - CHANGING DIRECTION", log: log, type: isDebugMode ? .fault : .info)
            changeDirection()
        } else {
            os_log("Click outside globe radius (distance: %f > hitRadius: %f)", log: log, type: isDebugMode ? .fault : .debug, distance, hitRadius)
        }
    }
    
    @objc private func handleClick(_ gestureRecognizer: NSGestureRecognizer) {
        let point = gestureRecognizer.location(in: sceneView)
        os_log("Gesture click at %{public}@", log: log, type: isDebugMode ? .fault : .info, String(describing: point))
        processClick(at: point)
    }
    
    private func changeDirection() {
        // Only change bounce direction if in bounce mode
        if bounceEnabled {
            // Calculate current angle
            let currentAngle = atan2(velocity.y, velocity.x)
            
            // Generate new angle 90 to 270 degrees away from current angle
            let angleOffset = CGFloat.random(in: CGFloat.pi/2...3*CGFloat.pi/2)
            let newAngle = currentAngle + angleOffset
            
            // Keep current speed but change direction significantly
            let currentSpeed = sqrt(pow(velocity.x, 2) + pow(velocity.y, 2))
            velocity = SCNVector3(
                x: CGFloat(cos(newAngle)) * currentSpeed,
                y: CGFloat(sin(newAngle)) * currentSpeed,
                z: 0
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let DEBUG_MODE = true  // Changed to public for access
    private let log = OSLog(subsystem: "Hello", category: "default")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if DEBUG_MODE {
            os_log("DEBUG MODE IS ENABLED", log: log, type: .fault)
        }
        
        setupMenu()
        
        guard let screen = NSScreen.main else {
            NSLog("No main screen detected")
            NSApp.terminate(nil)
            return
        }
        
        let screenSize = screen.frame
        let windowSize = NSSize(width: 800, height: 600)  // Larger initial window
        let windowOrigin = NSPoint(
            x: (screenSize.width - windowSize.width) / 2,
            y: (screenSize.height - windowSize.height) / 2
        )
        
        window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        if DEBUG_MODE {
            window.level = .floating  // Make window stay on top in debug mode
        }
        
        // Create globe view
        let globeView = GlobeView(frame: window.contentView!.bounds)
        globeView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(globeView)
        
        // Create a text label with larger font
        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        label.stringValue = "Hello World!"
        label.alignment = .center
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.textColor = .white
        
        // Make font size responsive to window size
        let fontSize = min(windowSize.width / 10, windowSize.height / 3)
        label.font = NSFont.boldSystemFont(ofSize: fontSize)
        
        // Center the label in the window
        label.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: window.contentView!.widthAnchor, multiplier: 0.9),
            label.heightAnchor.constraint(lessThanOrEqualTo: window.contentView!.heightAnchor, multiplier: 0.9)
        ])
        
        // Add notification observer for window resize
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            self?.updateFontSize()
        }
        
        // Set window properties
        window.title = "Hello World App"
        window.makeKeyAndOrderFront(nil)
        
        // Set minimum window size to ensure buttons are always visible
        window.minSize = NSSize(width: 480, height: 400)  // Increased from 200x150
        window.maxSize = screen.frame.size  // Use full screen dimensions as maximum
    }
    
    private func setupMenu() {
        let mainMenu = NSMenu()
        
        // Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        
        appMenu.addItem(NSMenuItem(title: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    private func updateFontSize() {
        guard let contentView = window.contentView,
              let label = contentView.subviews.first(where: { $0 is NSTextField }) as? NSTextField else {
            return
        }
        
        let fontSize = min(contentView.bounds.width / 10, contentView.bounds.height / 3)
        label.font = NSFont.boldSystemFont(ofSize: fontSize)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        guard window != nil else {
            NSLog("Window reference lost")
            return
        }
        window.orderFront(nil)
    }
}

// Create and start the application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()