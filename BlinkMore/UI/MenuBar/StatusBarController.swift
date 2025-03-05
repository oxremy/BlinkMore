//
//  StatusBarController.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import Foundation
import AppKit
import SwiftUI
import Combine

// Custom view for slider in menu using Auto Layout
class BetterMenuSliderView: NSView {
    private let stackView = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    
    var value: Double {
        get { return slider.doubleValue }
        set { 
            slider.doubleValue = newValue
            updateValueLabel()
        }
    }
    
    var onValueChanged: ((Double) -> Void)?
    private var customTextValues: [String]?
    private var unitText: String
    private var isDiscrete: Bool
    private var numberOfTickMarks: Int
    private var allowsMiddleValues: Bool
    
    init(title: String, minValue: Double, maxValue: Double, initialValue: Double, unitText: String = "seconds", 
         isDiscrete: Bool = false, numberOfTickMarks: Int = 0, allowsMiddleValues: Bool = true, customTextValues: [String]? = nil) {
        self.customTextValues = customTextValues
        self.unitText = unitText
        self.isDiscrete = isDiscrete
        self.numberOfTickMarks = numberOfTickMarks
        self.allowsMiddleValues = allowsMiddleValues
        
        super.init(frame: .zero)
        
        // Configure title label
        titleLabel.stringValue = "\(title):"
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        
        // Configure value label
        valueLabel.font = NSFont.systemFont(ofSize: 13)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.isEditable = false
        valueLabel.isSelectable = false
        valueLabel.isBordered = false
        valueLabel.backgroundColor = .clear
        valueLabel.alignment = .right
        valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        // Configure slider
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = initialValue
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        
        // Configure discrete behavior if requested
        if isDiscrete && numberOfTickMarks > 0 {
            slider.numberOfTickMarks = numberOfTickMarks
            slider.allowsTickMarkValuesOnly = !allowsMiddleValues
            slider.tickMarkPosition = .below
        }
        
        // Set up header row
        let headerStack = NSStackView(views: [titleLabel, valueLabel])
        headerStack.distribution = .fill
        headerStack.spacing = 8
        
        // Set up main stack
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 4
        stackView.addArrangedSubview(headerStack)
        stackView.addArrangedSubview(slider)
        
        // Make slider full width
        slider.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        headerStack.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        
        // Add to view with proper constraints
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        
        // Update value display
        updateValueLabel()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        // If discrete but not using tick marks only, snap to nearest integer or step
        if isDiscrete && !slider.allowsTickMarkValuesOnly && numberOfTickMarks > 1 {
            let range = slider.maxValue - slider.minValue
            let stepSize = range / Double(numberOfTickMarks - 1)
            
            // Calculate the nearest step value
            let steps = round((sender.doubleValue - slider.minValue) / stepSize)
            let snappedValue = slider.minValue + (steps * stepSize)
            
            // Only update if different (to avoid loops)
            if abs(sender.doubleValue - snappedValue) > 0.01 {
                sender.doubleValue = snappedValue
            }
        }
        
        updateValueLabel()
        onValueChanged?(sender.doubleValue)
    }
    
    private func updateValueLabel() {
        if let customTextValues = customTextValues, customTextValues.count >= 3 {
            // For a 3-value custom text array with min/med/max
            let normalizedValue = (slider.doubleValue - slider.minValue) / (slider.maxValue - slider.minValue)
            
            if normalizedValue >= 0.66 {
                valueLabel.stringValue = customTextValues[2] // "high" when slider is to the right
            } else if normalizedValue >= 0.33 {
                valueLabel.stringValue = customTextValues[1] // "med" in the middle
            } else {
                valueLabel.stringValue = customTextValues[0] // "low" when slider is to the left
            }
        } else if isDiscrete && unitText == "s" {
            // For time values, show as integers
            valueLabel.stringValue = "\(Int(round(slider.doubleValue)))\(unitText)"
        } else {
            // Default formatting
            valueLabel.stringValue = "\(Int(slider.doubleValue))\(unitText)"
        }
    }
}

// Custom view for color picker in menu using Auto Layout
class BetterMenuColorPickerView: NSView {
    private let stackView = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let colorWell = NSColorWell()
    
    var color: NSColor {
        get { return colorWell.color }
        set { colorWell.color = newValue }
    }
    
    var onColorChanged: ((NSColor) -> Void)?
    
    init(title: String, initialColor: NSColor) {
        super.init(frame: .zero)
        
        // Configure title label
        titleLabel.stringValue = "\(title):"
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        
        // Configure color well
        colorWell.color = initialColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        
        // Set fixed size for the color well
        colorWell.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let sizeConstraint = colorWell.widthAnchor.constraint(equalToConstant: 30)
        sizeConstraint.isActive = true
        colorWell.heightAnchor.constraint(equalTo: colorWell.widthAnchor).isActive = true
        
        // Set up stack view
        stackView.orientation = .horizontal
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.addArrangedSubview(titleLabel)
        
        // Add a spacer view for flexible spacing
        let spacerView = NSView()
        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stackView.addArrangedSubview(spacerView)
        
        stackView.addArrangedSubview(colorWell)
        
        // Add to view with proper constraints
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        
        // Observe color panel closing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelDidClose),
            name: NSColorPanel.willCloseNotification,
            object: nil
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func colorChanged(_ sender: NSColorWell) {
        onColorChanged?(sender.color)
    }
    
    @objc private func colorPanelDidClose(_ notification: Notification) {
        // Ensure we capture the final color
        onColorChanged?(colorWell.color)
    }
}

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var preferencesService = PreferencesService.shared
    private var fadeService = FadeService.shared
    private var eyeTrackingService: EyeTrackingService?
    
    private var fadeSpeedView: BetterMenuSliderView?
    private var blinkThresholdView: BetterMenuSliderView?
    private var earSensitivityView: BetterMenuSliderView?
    private var colorPickerView: BetterMenuColorPickerView?
    
    private var cancelBag = Set<AnyCancellable>()
    // Separate cancellable set specifically for eye tracking observations
    private var eyeTrackingCancelBag = Set<AnyCancellable>()
    
    // Icons for menu bar
    private let closedEyeImage: NSImage = {
        let image = NSImage(named: "ClosedEyeIcon") ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true // Allows the icon to adapt to menu bar appearance
        return image
    }()
    
    private let openEyeImage: NSImage = {
        let image = NSImage(named: "OpenEyeIcon") ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true // Allows the icon to adapt to menu bar appearance
        return image
    }()
    
    init() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set default icon
        if let button = statusItem.button {
            button.image = closedEyeImage
        }
        
        // Create menu
        menu = NSMenu()
        
        // Make menu stay visible when color well is clicked
        menu.autoenablesItems = false
        
        // Add preferences controls directly to the menu
        addPreferencesToMenu()
        
        menu.addItem(NSMenuItem.separator())
        
        // Add help menu item that explains how the app works
        let helpItem = NSMenuItem(title: "How It Works", action: #selector(showHowItWorks), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        
        // Add credit menu item at the bottom
        let creditItem = NSMenuItem(title: "", action: #selector(openGitHub), keyEquivalent: "")
        let creditAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let creditAttributedTitle = NSAttributedString(string: "Made with ❤️ by oxremy", attributes: creditAttributes)
        creditItem.attributedTitle = creditAttributedTitle
        creditItem.target = self
        menu.addItem(creditItem)
        
        // Add Quit button
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Set the menu
        statusItem.menu = menu
        
        // Subscribe to preferences changes to keep UI in sync
        preferencesService.$fadeColor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newColor in
                // Update color picker UI when preference changes externally
                self?.colorPickerView?.color = newColor
            }
            .store(in: &cancelBag)
        
        // Subscribe to EAR sensitivity changes
        preferencesService.$earSensitivity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                // Update sensitivity slider UI when preference changes externally
                self?.earSensitivityView?.value = newValue
            }
            .store(in: &cancelBag)
        
        // Listen for eye tracking preference changes - optimize with debounce
        preferencesService.$eyeTrackingEnabled
            .removeDuplicates() // Only process actual changes
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main) // Prevent rapid toggling
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.initializeEyeTracking()
                } else {
                    // Cancel any pending fade operations
                    self?.fadeDelayWorkItem?.cancel()
                    self?.fadeDelayWorkItem = nil
                    
                    // Cancel all eye tracking subscriptions
                    self?.eyeTrackingCancelBag.removeAll()
                    
                    self?.eyeTrackingService?.stopTracking()
                    self?.eyeTrackingService = nil
                    
                    // Reset icon to closed eye - only if needed
                    if let button = self?.statusItem.button,
                       button.image != self?.closedEyeImage {
                        button.image = self?.closedEyeImage
                    }
                }
                
                // Update the menu item state
                if let eyeTrackingItem = self?.menu.items.first(where: { $0.title == "Enable Eye Tracking" }) {
                    eyeTrackingItem.state = enabled ? .on : .off
                }
            }
            .store(in: &cancelBag)
        
        // Make sure color panel is closed when menu closes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuWillClose),
            name: NSMenu.didEndTrackingNotification,
            object: menu
        )
    }
    
    deinit {
        // Clean up notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Clean up cancellables
        cancelBag.removeAll()
        eyeTrackingCancelBag.removeAll()
        
        // Make sure color panel is closed
        if NSColorPanel.shared.isVisible {
            NSColorPanel.shared.close()
        }
    }
    
    private func addPreferencesToMenu() {
        // Add section header for features (moved to top)
        let featuresHeader = createSectionHeader("Features")
        menu.addItem(featuresHeader)
        
        // Add Eye Tracking toggle as a separate menu item (moved to top)
        let eyeTrackingItem = NSMenuItem(title: "Enable Eye Tracking", action: #selector(toggleEyeTracking(_:)), keyEquivalent: "")
        eyeTrackingItem.state = preferencesService.eyeTrackingEnabled ? .on : .off
        eyeTrackingItem.target = self
        menu.addItem(eyeTrackingItem)
        
        // Blink Threshold slider
        let blinkThresholdItem = NSMenuItem()
        let blinkThresholdView = BetterMenuSliderView(
            title: "Time Between Blinks",
            minValue: Constants.minBlinkThreshold,
            maxValue: Constants.maxBlinkThreshold,
            initialValue: preferencesService.blinkThreshold,
            unitText: "s",
            isDiscrete: true,
            numberOfTickMarks: 10,  // 10 tick marks for values between 3-12
            allowsMiddleValues: false
        )
        blinkThresholdView.onValueChanged = { [weak self] newValue in
            self?.preferencesService.blinkThreshold = newValue
        }
        blinkThresholdView.frame = NSRect(x: 0, y: 0, width: 280, height: 70)
        blinkThresholdItem.view = blinkThresholdView
        menu.addItem(blinkThresholdItem)
        self.blinkThresholdView = blinkThresholdView
        
        // Fade Speed slider (moved below Time Between Blinks)
        let fadeSpeedItem = NSMenuItem()
        let fadeSpeedView = BetterMenuSliderView(
            title: "Fade Duration",
            minValue: Constants.minFadeSpeed,
            maxValue: Constants.maxFadeSpeed,
            initialValue: preferencesService.fadeSpeed,
            unitText: "s",
            isDiscrete: true,
            numberOfTickMarks: 5,  // 5 tick marks for 1, 2, 3, 4, 5 seconds
            allowsMiddleValues: false
        )
        fadeSpeedView.onValueChanged = { [weak self] newValue in
            self?.preferencesService.fadeSpeed = newValue
        }
        fadeSpeedView.frame = NSRect(x: 0, y: 0, width: 280, height: 70)
        fadeSpeedItem.view = fadeSpeedView
        menu.addItem(fadeSpeedItem)
        self.fadeSpeedView = fadeSpeedView
        
        // Add EAR Sensitivity slider with custom labels
        let earSensitivityItem = NSMenuItem()
        let earSensitivityView = BetterMenuSliderView(
            title: "Blink Sensitivity",
            minValue: Constants.minEARSensitivity,
            maxValue: Constants.maxEARSensitivity,
            initialValue: preferencesService.earSensitivity,
            unitText: "",
            isDiscrete: true,
            numberOfTickMarks: 3,  // 3 tick marks for low, med, high
            allowsMiddleValues: false,
            customTextValues: ["low", "med", "high"]
        )
        earSensitivityView.onValueChanged = { [weak self] newValue in
            self?.preferencesService.earSensitivity = newValue
        }
        earSensitivityView.frame = NSRect(x: 0, y: 0, width: 280, height: 70)
        earSensitivityItem.view = earSensitivityView
        menu.addItem(earSensitivityItem)
        self.earSensitivityView = earSensitivityView
        
        // Add Fade Color picker with improved layout (moved to bottom)
        let colorPickerItem = NSMenuItem()
        let colorPickerView = BetterMenuColorPickerView(
            title: "Fade Color",
            initialColor: preferencesService.fadeColor
        )
        colorPickerView.onColorChanged = { [weak self] newColor in
            DispatchQueue.main.async {
                self?.preferencesService.fadeColor = newColor
            }
        }
        colorPickerView.frame = NSRect(x: 0, y: 0, width: 280, height: 50)
        colorPickerItem.view = colorPickerView
        menu.addItem(colorPickerItem)
        self.colorPickerView = colorPickerView
    }
    
    // Helper to create section headers using standard system styling
    private func createSectionHeader(_ title: String) -> NSMenuItem {
        // Create a section header menu item using the standard system appearance
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        
        // Use system font with standard header styling
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        
        // Create attributed title
        item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        
        // Disable the item so it can't be selected
        item.isEnabled = false
        
        return item
    }
    
    @objc private func showHowItWorks() {
        // Create a panel-style window
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 340),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.title = "How BlinkMore Works"
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.level = NSWindow.Level.floating
        
        // Position window below menu bar near the status item
        if let button = statusItem.button, let frame = button.window?.frame {
            let xPosition = frame.origin.x
            window.setFrameTopLeftPoint(NSPoint(x: xPosition, y: frame.origin.y - 10))
        } else {
            window.center()
        }
        
        // Create the content
        let contentView = NSHostingView(rootView: HowItWorksView())
        window.contentView = contentView
        
        // Show the window
        window.makeKeyAndOrderFront(nil as AnyObject?)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func toggleEyeTracking(_ sender: NSMenuItem) {
        // Toggle eye tracking state
        let enabled = sender.state != .on
        
        if enabled {
            // If turning on, check permissions first
            PermissionsService.shared.checkCameraAccess { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        sender.state = .on
                        self?.preferencesService.eyeTrackingEnabled = true
                    } else {
                        // If permission denied, keep it off
                        sender.state = .off
                        self?.preferencesService.eyeTrackingEnabled = false
                        
                        // Show alert
                        let alert = NSAlert()
                        alert.messageText = "Camera Access Required"
                        alert.informativeText = "Eye tracking requires camera access. Would you like to open System Settings?"
                        alert.addButton(withTitle: "Open Settings")
                        alert.addButton(withTitle: "Cancel")
                        
                        if alert.runModal() == .alertFirstButtonReturn {
                            PermissionsService.shared.openSystemPreferences()
                        }
                    }
                }
            }
        } else {
            // Simply turn it off
            sender.state = .off
            self.preferencesService.eyeTrackingEnabled = false
        }
    }
    
    private func initializeEyeTracking() {
        // First check if we have camera permission
        PermissionsService.shared.checkCameraAccess { [weak self] granted in
            guard let self = self else { return }
            
            if granted {
                DispatchQueue.main.async {
                    // Create the eye tracking service
                    self.eyeTrackingService = EyeTrackingService()
                    
                    // Don't start tracking until service is fully initialized
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.eyeTrackingService?.startTracking()
                        
                        // Set up observers for eye state changes
                        self.setupEyeTrackingObservers()
                    }
                }
            } else {
                // Update UI to show eye tracking is disabled due to permissions
                DispatchQueue.main.async {
                    // Disable eye tracking in preferences since we don't have permission
                    self.preferencesService.eyeTrackingEnabled = false
                    
                    // Update menu item state
                    if let eyeTrackingItem = self.menu.items.first(where: { $0.title == "Enable Eye Tracking" }) {
                        eyeTrackingItem.state = .off
                    }
                    
                    // Set closed eye icon
                    if let button = self.statusItem.button {
                        button.image = self.closedEyeImage
                    }
                }
            }
        }
    }
    
    private func setupEyeTrackingObservers() {
        // Make sure we have a valid service before proceeding
        guard let service = eyeTrackingService else {
            print("Warning: Attempted to setup observers with nil eye tracking service")
            return
        }
        
        // Cancel any existing eye tracking subscriptions first
        eyeTrackingCancelBag.removeAll()
        
        // Optimize eye state monitoring with better Combine operators
        service.$isEyeOpen
            .removeDuplicates() // Prevent redundant updates for the same state
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main) // Reduced debounce time for faster response
            .receive(on: DispatchQueue.main) // Ensure UI updates happen on main thread
            .sink { [weak self] isOpen in
                guard let self = self else { return }
                
                // Update icon based on eye state - only when needed
                if let button = self.statusItem.button, 
                   button.image != (isOpen ? self.openEyeImage : self.closedEyeImage) {
                    button.image = isOpen ? self.openEyeImage : self.closedEyeImage
                    print("Status bar icon updated to: \(isOpen ? "OPEN EYE" : "CLOSED EYE")")
                }
                
                // Create a cancellable for the delayed fade so we can cancel it if state changes
                if isOpen {
                    // Cancel any existing fade timer
                    self.fadeDelayWorkItem?.cancel()
                    
                    // Create new work item for delayed fade
                    let threshold = self.preferencesService.blinkThreshold
                    let workItem = DispatchWorkItem { [weak self] in
                        // Only apply fade if eyes are still open
                        if self?.eyeTrackingService?.isEyeOpen == true {
                            print("APPLYING FADE: Eye open threshold (\(threshold)s) exceeded")
                            self?.fadeService.applyFade()
                        }
                    }
                    
                    // Store workitem for potential cancellation
                    self.fadeDelayWorkItem = workItem
                    
                    // Schedule the delayed fade
                    DispatchQueue.main.asyncAfter(deadline: .now() + threshold, execute: workItem)
                    print("Scheduled fade timer with \(threshold)s threshold")
                } else {
                    // Cancel any pending fade
                    if let workItem = self.fadeDelayWorkItem, !workItem.isCancelled {
                        print("Cancelling pending fade timer")
                        workItem.cancel()
                    }
                    self.fadeDelayWorkItem = nil
                    
                    // Force immediate fade removal when eyes close
                    if self.fadeService.isFaded {
                        print("REMOVING FADE: Eyes closed")
                        self.fadeService.removeFade()
                    }
                }
            }
            .store(in: &eyeTrackingCancelBag)
    }
    
    // Work item for delayed fade action
    private var fadeDelayWorkItem: DispatchWorkItem?
    
    @objc private func quitApplication() {
        NSApplication.shared.terminate(self)
    }
    
    @objc private func openGitHub() {
        NSWorkspace.shared.open(Constants.authorURL)
    }
    
    @objc private func menuWillClose(_ notification: Notification) {
        // when the menu closes - this follows standard macOS behavior
    }
    
    // Add a new public method to start eye tracking after permissions are verified
    func initializeEyeTrackingIfEnabled() {
        if preferencesService.eyeTrackingEnabled {
            initializeEyeTracking()
        }
    }
}

// SwiftUI view for the help content
struct HowItWorksView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BlinkMore uses your camera to detect when you're not blinking enough.")
                .multilineTextAlignment(.leading)
            
            Text("When your eyes stay open too long, the screen gradually fades as a gentle reminder to blink regularly, helping keep your eyes moisturized and reducing eye strain.")
                .multilineTextAlignment(.leading)
                .padding(.bottom, 4)
            
            Text("Blink Sensitivity:")
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("• Low: Only detects pronounced blinks")
                Text("• Med: Balanced sensitivity for most users")
                Text("• High: Detects even subtle eye closures")
            }
            .padding(.leading, 8)
            
            Text("Works best with a clear view of your eyes on Mac's built-in camera.")
                .padding(.top, 4)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button("Close") {
                if let window = NSApplication.shared.keyWindow {
                    window.close()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .padding()
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
    }
}
