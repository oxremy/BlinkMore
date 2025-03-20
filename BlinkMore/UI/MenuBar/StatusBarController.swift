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

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var preferencesService = PreferencesService.shared
    private var fadeService = FadeService.shared
    private var eyeTrackingService: EyeTrackingService?
    
    private var fadeSpeedView: BetterMenuSliderView?
    private var blinkThresholdView: BetterMenuSliderView?
    private var earSensitivityView: BetterMenuSliderView?
    
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
                // Update color menu item states when preference changes externally
                self?.updateColorMenuItemStates(newColor)
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
    }
    
    deinit {
        // Clean up notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Clean up cancellables
        cancelBag.removeAll()
        eyeTrackingCancelBag.removeAll()
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
        
        // Add Fade Color submenu with predefined colors
        let colorMenuItem = NSMenuItem(title: "Fade Color", action: nil, keyEquivalent: "")
        
        // Create submenu for colors
        let colorsSubmenu = NSMenu()
        
        // Define our 9 predefined colors
        let predefinedColors: [(name: String, color: NSColor)] = [
            ("Black", .black),
            ("Gray", .gray),
            ("White", .white),
            ("Red", NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)),
            ("Purple", NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.8, alpha: 1.0)),
            ("Blue", NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.9, alpha: 1.0)),
            ("Green", NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)),
            ("Yellow", NSColor(calibratedRed: 0.9, green: 0.8, blue: 0.2, alpha: 1.0)),
            ("Orange", NSColor(calibratedRed: 0.9, green: 0.5, blue: 0.1, alpha: 1.0))
        ]
        
        // Add each color as a menu item
        for (name, color) in predefinedColors {
            let colorItem = NSMenuItem(title: name, action: #selector(colorMenuItemSelected(_:)), keyEquivalent: "")
            colorItem.target = self
            
            // Create a small colored view to show the color
            let colorView = NSView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
            colorView.wantsLayer = true
            colorView.layer?.backgroundColor = color.cgColor
            colorView.layer?.cornerRadius = 7 // Make it round
            colorView.layer?.borderWidth = 1
            colorView.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
            
            // Create an image from the view
            let colorImage = NSImage(size: colorView.bounds.size)
            colorImage.lockFocus()
            colorView.layer?.render(in: NSGraphicsContext.current!.cgContext)
            colorImage.unlockFocus()
            
            // Set the image and add a tag to identify the color
            colorItem.image = colorImage
            
            // Store the color as a property of the menu item
            colorItem.representedObject = color
            
            // Check the current color
            if self.preferencesService.fadeColor.isClose(to: color) {
                colorItem.state = .on
            }
            
            colorsSubmenu.addItem(colorItem)
        }
        
        // Set the submenu to the menu item
        colorMenuItem.submenu = colorsSubmenu
        menu.addItem(colorMenuItem)
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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.title = "How BlinkMore Works"
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.level = NSWindow.Level.floating
        
        // Position window at top center of screen
        if let screenFrame = NSScreen.main?.visibleFrame {
            let windowWidth = window.frame.width
            let xPosition = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            let yPosition = screenFrame.origin.y + screenFrame.height - 10 // 10px from top of screen
            window.setFrameTopLeftPoint(NSPoint(x: xPosition, y: yPosition))
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
        // First prepare for termination
        prepareForAppTermination()
        
        // Then terminate the app
        NSApplication.shared.terminate(self)
    }
    
    @objc private func openGitHub() {
        NSWorkspace.shared.open(Constants.authorURL)
    }
    
    // Add a new method to update menu item states when color changes externally
    private func updateColorMenuItemStates(_ newColor: NSColor) {
        // Find the Fade Color menu item
        if let colorMenuItem = menu.items.first(where: { $0.title == "Fade Color" }),
           let submenu = colorMenuItem.submenu {
            // Update all submenu items
            for item in submenu.items {
                if let itemColor = item.representedObject as? NSColor {
                    item.state = newColor.isClose(to: itemColor) ? .on : .off
                }
            }
        }
    }
    
    // Add a public method to start eye tracking after permissions are verified
    func initializeEyeTrackingIfEnabled() {
        if preferencesService.eyeTrackingEnabled {
            initializeEyeTracking()
        }
    }
    
    // Add this method to handle color selection
    @objc private func colorMenuItemSelected(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? NSColor else { return }
        
        // Update preferences and apply color
        preferencesService.fadeColor = color
        fadeService.updateFadeColor(color, animated: true)
        
        // Update menu item states
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = (item == sender) ? .on : .off
            }
        }
    }
    
    // Add this new method for app termination preparation
    func prepareForAppTermination() {
        print("Preparing StatusBarController for app termination")
        
        // Cancel any pending fade operations
        fadeDelayWorkItem?.cancel()
        fadeDelayWorkItem = nil
        
        // Cancel all eye tracking subscriptions first
        eyeTrackingCancelBag.removeAll()
        
        // Stop eye tracking and ensure it's properly cleaned up
        if let trackingService = eyeTrackingService {
            // Use the new prepareForTermination method we added
            trackingService.prepareForTermination()
        }
        
        // Release the service reference
        eyeTrackingService = nil
        
        print("StatusBarController termination preparation completed")
    }
}

// SwiftUI view for the help content
struct HowItWorksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("BlinkMoreFree is an open source macOS menu bar application that helps reduce eye strain by fading your screen when you stare at it for too long without blinking. Using automated eye-tracking and customized settings to encourage you to blink more.")
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                Text("Requirements:")
                    .fontWeight(.medium)
                    .padding(.top, 8)
                    .multilineTextAlignment(.leading)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text("•")
                        Text("macOS 14 (Sonoma) or later")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    HStack(alignment: .top) {
                        Text("•")
                        Text("Uses Mac's built-in front facing camera")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Text("Privacy:")
                    .fontWeight(.medium)
                    .padding(.top, 8)
                    .multilineTextAlignment(.leading)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text("•")
                        Text("Everything happens right on your Mac—no data leaves your device or sticks around after you close the app. No accounts or personal information needed.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Text("Tips for Best Experience:")
                    .fontWeight(.medium)
                    .padding(.top, 8)
                    .multilineTextAlignment(.leading)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text("•")
                        Text("Make sure your Mac's camera has a clear view of your eyes (heads-up: glasses at certain angles may have reflections that obstruct camera view).")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    HStack(alignment: .top) {
                        Text("•")
                        Text("Consider the angle of your camera. Blink detection may not work at extreme angles, like laying in bed with Mac on your lap.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    HStack(alignment: .top) {
                        Text("•")
                        Text("BlinkMoreFree is perfect for text-heavy tasks like reading––just know it uses a good chunk of your Mac's power.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
    }
}

// Add this extension to NSColor to check for similar colors (since exact matches might not work)
extension NSColor {
    func isClose(to other: NSColor) -> Bool {
        // Convert both colors to the same color space for comparison
        guard let selfRGB = self.usingColorSpace(.sRGB),
              let otherRGB = other.usingColorSpace(.sRGB) else {
            return false
        }
        
        // Get RGB components
        var selfRed: CGFloat = 0
        var selfGreen: CGFloat = 0
        var selfBlue: CGFloat = 0
        var otherRed: CGFloat = 0
        var otherGreen: CGFloat = 0
        var otherBlue: CGFloat = 0
        
        selfRGB.getRed(&selfRed, green: &selfGreen, blue: &selfBlue, alpha: nil)
        otherRGB.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: nil)
        
        // Check if the colors are close enough (using a threshold)
        let threshold: CGFloat = 0.1
        let redDiff = abs(selfRed - otherRed)
        let greenDiff = abs(selfGreen - otherGreen)
        let blueDiff = abs(selfBlue - otherBlue)
        
        return redDiff < threshold && greenDiff < threshold && blueDiff < threshold
    }
}
