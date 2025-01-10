import Cocoa
import SceneKit

class GlobeView: NSView {
    private var sceneView: SCNView!
    private var sphereNode: SCNNode!  // Changed from array to single node
    private var currentTexture: EarthTexture = .blueMarble  // Default
    private var textureButtons: [NSButton] = []  // Add this line
    private var updateLabels: [NSTextField] = []
    private var updateTimer: Timer?
    
    // Add last update time tracking
    private var lastUpdateTimes: [EarthTexture: Date] = [:]
    
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
    
    // Load saved state
    private func loadSavedState() -> EarthTexture {
        let defaults = UserDefaults.standard
        if let savedValue = defaults.string(forKey: "selectedTexture"),
           let texture = EarthTexture(rawValue: savedValue) {
            return texture
        }
        return .blueMarble
    }
    
    // Save state
    private func saveState(_ texture: EarthTexture) {
        UserDefaults.standard.set(texture.rawValue, forKey: "selectedTexture")
    }
    
    // Update texture
    private func updateTexture(_ texture: EarthTexture) {
        currentTexture = texture
        if let image = Assets.earthTexture(for: texture) {
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.isDoubleSided = true
            sphereNode.geometry?.materials = [material]
            updateLastUpdateTime(for: texture)
        }
        saveState(texture)
    }
    
    private func startUpdateTimer() {
        // Update every 10 minutes (600 seconds)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.refreshCurrentTexture()
        }
    }
    
    private func refreshCurrentTexture() {
        // Only refresh GOES images
        if currentTexture != .blueMarble {
            updateTexture(currentTexture)
            updateLastUpdateTime(for: currentTexture)
        }
    }
    
    private func updateLastUpdateTime(for texture: EarthTexture) {
        lastUpdateTimes[texture] = Date()
        updateTimeLabels()
    }
    
    private func updateTimeLabels() {
        for (index, texture) in [EarthTexture.blueMarble, .goesEast, .goesWest].enumerated() {
            let baseText = Assets.metadata[texture]?.updateFrequency ?? ""
            if texture != .blueMarble, let lastUpdate = lastUpdateTimes[texture] {
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
        super.init(frame: frameRect)
        setupScene()
        
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
        
        // Create Scene
        let scene = SCNScene()
        sceneView.scene = scene
        
        // Create single globe
        let sphere = SCNSphere(radius: 1.0)
        sphere.segmentCount = 96
        
        sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)
        
        // Add rotation animation
        let rotation = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 8)
        let repeatRotation = SCNAction.repeatForever(rotation)
        sphereNode.runAction(repeatRotation)
        
        // Camera setup
        let cameraNode = SCNNode()
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
        let buttonContainerHeight: CGFloat = 100
        let buttonContainer = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: buttonContainerHeight
        ))
        buttonContainer.autoresizingMask = [.width, .minYMargin]  // Stick to bottom, stretch width
        addSubview(buttonContainer)
        
        // Button dimensions
        let buttonHeight: CGFloat = 30
        let buttonSpacing: CGFloat = 20  // Space between buttons
        let textureButtonWidth: CGFloat = 150  // Fixed width for texture buttons
        
        // Calculate total width needed for texture buttons
        let totalTextureButtonsWidth = (textureButtonWidth * 3) + (buttonSpacing * 2)
        
        // Calculate starting X to center the texture buttons group
        let startX = (buttonContainer.bounds.width - totalTextureButtonsWidth) / 2
        
        let textures: [EarthTexture] = [.blueMarble, .goesEast, .goesWest]
        
        // Create texture buttons
        for (index, texture) in textures.enumerated() {
            let x = startX + (textureButtonWidth + buttonSpacing) * CGFloat(index)
            
            let button = NSButton(frame: NSRect(
                x: x,
                y: 50,  // Fixed Y position for texture buttons
                width: textureButtonWidth,
                height: buttonHeight
            ))
            button.title = texture.rawValue
            button.bezelStyle = .regularSquare
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.tag = index
            buttonContainer.addSubview(button)
            textureButtons.append(button)
            
            // Add update label below the texture button
            let label = NSTextField(frame: NSRect(
                x: x,
                y: 30,  // Fixed Y position for labels
                width: textureButtonWidth,
                height: 20
            ))
            label.stringValue = Assets.metadata[texture]?.updateFrequency ?? ""
            label.alignment = .center
            label.isBezeled = false
            label.isEditable = false
            label.drawsBackground = false
            label.textColor = .gray
            label.font = NSFont.systemFont(ofSize: 10)
            buttonContainer.addSubview(label)
            updateLabels.append(label)
        }
        
        // Add Bounce button centered below other buttons
        let bounceButtonWidth: CGFloat = 100
        let bounceButton = NSButton(frame: NSRect(
            x: (buttonContainer.bounds.width - bounceButtonWidth) / 2,  // Center horizontally
            y: 10,  // Fixed Y position for bounce button
            width: bounceButtonWidth,
            height: buttonHeight
        ))
        bounceButton.title = "Bounce!"
        bounceButton.bezelStyle = .regularSquare
        bounceButton.target = self
        bounceButton.action = #selector(bounceButtonClicked(_:))
        bounceButton.state = bounceEnabled ? .on : .off
        buttonContainer.addSubview(bounceButton)
        self.bounceButton = bounceButton
        
        // Add auto-layout constraints to keep buttons centered
        buttonContainer.subviews.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        
        // Center the button container itself
        NSLayoutConstraint.activate([
            buttonContainer.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            buttonContainer.widthAnchor.constraint(equalTo: self.widthAnchor)
        ])
        
        // Load and apply saved texture
        currentTexture = loadSavedState()
        updateTexture(currentTexture)
        updateButtonStates()
    }
    
    @objc private func buttonClicked(_ sender: NSButton) {
        guard let texture = EarthTexture(rawValue: sender.title) else { return }
        updateTexture(texture)
        updateButtonStates()
    }
    
    private func updateButtonStates() {
        for button in textureButtons {
            button.state = button.title == currentTexture.rawValue ? .on : .off
        }
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
    
    private func startBouncing() {
        // Stop rotation animation
        sphereNode.removeAllActions()
        
        // Start bounce timer
        bounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateBouncePosition()
        }
    }
    
    private func stopBouncing() {
        // Stop bounce timer
        bounceTimer?.invalidate()
        bounceTimer = nil
        
        // Return to center
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5  // Smooth transition
        sphereNode.position = SCNVector3Zero
        SCNTransaction.commit()
        
        // Restore rotation animation
        let rotation = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 8)
        let repeatRotation = SCNAction.repeatForever(rotation)
        sphereNode.runAction(repeatRotation)
    }
    
    private func updateBouncePosition() {
        let currentPosition = sphereNode.presentation.position
        var newPosition = currentPosition
        
        // Update position
        newPosition.x += velocity.x * 0.02
        newPosition.y += velocity.y * 0.02
        
        // Use dynamic bounds that account for window size
        let effectiveBoundsX = boundsX - sphereRadius
        let effectiveBoundsY = boundsY - sphereRadius
        
        // Check x bounds considering sphere radius
        if Float(abs(newPosition.x)) + sphereRadius > effectiveBoundsX + sphereRadius {
            velocity.x *= -1
            newPosition.x = newPosition.x > 0 ? 
                CGFloat(effectiveBoundsX) : 
                CGFloat(-effectiveBoundsX)
        }
        
        // Check y bounds considering sphere radius
        if Float(abs(newPosition.y)) + sphereRadius > effectiveBoundsY + sphereRadius {
            velocity.y *= -1
            newPosition.y = newPosition.y > 0 ? 
                CGFloat(effectiveBoundsY) : 
                CGFloat(-effectiveBoundsY)
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
        let aspectRatio = Float(bounds.width / bounds.height)
        boundsX = 3.5 * aspectRatio
        boundsY = 2.5
        
        // If globe is outside new bounds, move it inside
        if abs(sphereNode.position.x) > CGFloat(boundsX) {
            sphereNode.position.x = sphereNode.position.x > 0 ? CGFloat(boundsX) : CGFloat(-boundsX)
        }
        if abs(sphereNode.position.y) > CGFloat(boundsY) {
            sphereNode.position.y = sphereNode.position.y > 0 ? CGFloat(boundsY) : CGFloat(-boundsY)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        
        window.minSize = NSSize(width: 200, height: 150)
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