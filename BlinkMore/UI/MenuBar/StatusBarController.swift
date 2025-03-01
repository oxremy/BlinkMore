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

// Custom view for slider in menu
class MenuSliderView: NSView {
    private var titleLabel: NSTextField
    private var slider: NSSlider
    private var valueLabel: NSTextField
    private var minLabel: NSTextField?
    private var maxLabel: NSTextField?
    private var unitText: String
    
    var value: Double {
        get { return slider.doubleValue }
        set { 
            slider.doubleValue = newValue
            updateValueLabel()
        }
    }
    
    var onValueChanged: ((Double) -> Void)?
    
    init(frame frameRect: NSRect, title: String, minValue: Double, maxValue: Double, initialValue: Double, unitText: String = "seconds") {
        self.unitText = unitText
        
        // Create the title label
        titleLabel = NSTextField(labelWithString: "\(title):")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        
        // Create the slider
        slider = NSSlider(value: initialValue, minValue: minValue, maxValue: maxValue, target: nil, action: #selector(sliderChanged(_:)))
        
        // Create the value label
        valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.isEditable = false
        valueLabel.isSelectable = false
        valueLabel.isBordered = false
        valueLabel.backgroundColor = .clear
        valueLabel.alignment = .right
        
        super.init(frame: frameRect)
        
        addSubview(titleLabel)
        addSubview(slider)
        addSubview(valueLabel)
        
        slider.target = self
        
        updateValueLabel()
        layout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        let padding: CGFloat = 10
        let labelWidth: CGFloat = 170
        let valueWidth: CGFloat = 40
        
        // Position title label
        titleLabel.frame = NSRect(
            x: padding,
            y: bounds.height - 30,
            width: labelWidth,
            height: 20
        )
        
        // Position value label
        valueLabel.frame = NSRect(
            x: bounds.width - padding - valueWidth,
            y: bounds.height - 30,
            width: valueWidth,
            height: 20
        )
        
        // Position slider
        slider.frame = NSRect(
            x: padding,
            y: bounds.height - 55,
            width: bounds.width - (padding * 2),
            height: 20
        )
    }
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        updateValueLabel()
        onValueChanged?(sender.doubleValue)
    }
    
    private func updateValueLabel() {
        valueLabel.stringValue = "\(Int(slider.doubleValue))s"
    }
}

// Custom view for color picker in menu
class MenuColorPickerView: NSView {
    private var titleLabel: NSTextField
    private var colorWell: NSColorWell
    private var currentColor: NSColor
    
    var color: NSColor {
        get { return currentColor }
        set { 
            currentColor = newValue
            colorWell.color = newValue
        }
    }
    
    var onColorChanged: ((NSColor) -> Void)?
    
    init(frame frameRect: NSRect, title: String, initialColor: NSColor) {
        // Create the title label
        titleLabel = NSTextField(labelWithString: "\(title):")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        
        // Create NSColorWell - this is the standard macOS color picker control
        colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        colorWell.color = initialColor
        colorWell.isBordered = true
        
        currentColor = initialColor
        
        super.init(frame: frameRect)
        
        // Configure the color well and panel
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        
        // Configure the color panel
        NSColorPanel.shared.showsAlpha = true
        NSColorPanel.shared.setTarget(self)
        NSColorPanel.shared.setAction(#selector(colorPanelChanged))
        
        // Add subviews
        addSubview(titleLabel)
        addSubview(colorWell)
        
        // Set up the color panel to work with our color well
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelDidClose),
            name: NSColorPanel.willCloseNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        let padding: CGFloat = 10
        
        // Position title label
        titleLabel.frame = NSRect(
            x: padding,
            y: (bounds.height - 20) / 2,
            width: 100,
            height: 20
        )
        
        // Position color well
        colorWell.frame = NSRect(
            x: bounds.width - padding - 30,
            y: (bounds.height - 30) / 2,
            width: 30,
            height: 30
        )
    }
    
    @objc private func colorChanged(_ sender: NSColorWell) {
        // Update the current color
        currentColor = sender.color
        
        // Notify observers
        onColorChanged?(currentColor)
        
        print("Color changed to: \(currentColor)")
    }
    
    // Modified mouse handling to properly open the color panel
    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        
        if colorWell.frame.contains(localPoint) {
            // Directly open the color panel without relying on NSColorWell's handling
            if !NSColorPanel.shared.isVisible {
                NSColorPanel.shared.setTarget(self)
                NSColorPanel.shared.setAction(#selector(colorPanelChanged))
                NSColorPanel.shared.color = colorWell.color
                
                // Make color panel visible on top
                NSColorPanel.shared.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                
                // This line is important - it keeps the menu open
                NSApp.mainMenu?.cancelTracking()
            }
        } else {
            super.mouseDown(with: event)
        }
    }
    
    @objc private func colorPanelChanged() {
        // Capture color changes from the color panel
        let newColor = NSColorPanel.shared.color
        colorWell.color = newColor
        currentColor = newColor
        onColorChanged?(newColor)
    }
    
    @objc private func colorPanelDidClose(_ notification: Notification) {
        print("Color panel closed")
    }
}

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var preferencesService = PreferencesService.shared
    private var fadeService = FadeService.shared
    private var eyeTrackingService: EyeTrackingService?
    
    private var fadeSpeedView: MenuSliderView?
    private var blinkThresholdView: MenuSliderView?
    private var colorPickerView: MenuColorPickerView?
    
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
        
        // Set up local event monitor for clicks that should keep the menu open
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved]) { event in
            // Prevent menu from closing when interacting with color panel
            if NSColorPanel.shared.isVisible {
                // Don't interfere with events in the color panel itself
                if NSApp.mainWindow === NSColorPanel.shared {
                    return event
                }
                
                // Prevent menu from closing by canceling tracking
                if NSMenu.menuBarVisible() {
                    // Check if click is outside the menu and not in the color panel
                    let clickedWindow = NSApp.window(withWindowNumber: event.windowNumber)
                    
                    // If the clicked window is not the color panel, keep the panel visible
                    if clickedWindow != NSColorPanel.shared {
                        // Keep the color panel visible
                        NSColorPanel.shared.orderFront(nil)
                        return nil // Eat the event to keep menu open
                    }
                }
            }
            return event
        }
        
        // Add preferences controls directly to the menu
        addPreferencesToMenu()
        
        menu.addItem(NSMenuItem.separator())
        
        // Create credit menu item with smaller text
        let creditItem = NSMenuItem(title: "", action: #selector(openGitHub), keyEquivalent: "")
        let creditFont = NSFont.systemFont(ofSize: 11, weight: .regular) // Smaller font size
        let creditAttributes: [NSAttributedString.Key: Any] = [
            .font: creditFont,
            .foregroundColor: NSColor.labelColor
        ]
        let creditAttributedTitle = NSAttributedString(string: "Made with ❤️ by oxremy", attributes: creditAttributes)
        creditItem.attributedTitle = creditAttributedTitle
        creditItem.target = self
        menu.addItem(creditItem)
        
        // Set the menu
        statusItem.menu = menu
        
        // Initialize eye tracking service if enabled
        if preferencesService.eyeTrackingEnabled {
            initializeEyeTracking()
        }
        
        // Subscribe to preferences changes to keep UI in sync
        preferencesService.$fadeColor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newColor in
                // Update color picker UI when preference changes externally
                self?.colorPickerView?.color = newColor
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
        // Fade Speed slider
        let fadeSpeedItem = NSMenuItem()
        let fadeSpeedView = MenuSliderView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 80),
            title: "Fade Speed",
            minValue: Constants.minFadeSpeed,
            maxValue: Constants.maxFadeSpeed,
            initialValue: preferencesService.fadeSpeed,
            unitText: "s"
        )
        fadeSpeedView.onValueChanged = { [weak self] newValue in
            self?.preferencesService.fadeSpeed = newValue
        }
        fadeSpeedItem.view = fadeSpeedView
        menu.addItem(fadeSpeedItem)
        self.fadeSpeedView = fadeSpeedView
        
        // Blink Threshold slider
        let blinkThresholdItem = NSMenuItem()
        let blinkThresholdView = MenuSliderView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 80),
            title: "Time Between Blinks",
            minValue: Constants.minBlinkThreshold,
            maxValue: Constants.maxBlinkThreshold,
            initialValue: preferencesService.blinkThreshold,
            unitText: "s"
        )
        blinkThresholdView.onValueChanged = { [weak self] newValue in
            self?.preferencesService.blinkThreshold = newValue
        }
        blinkThresholdItem.view = blinkThresholdView
        menu.addItem(blinkThresholdItem)
        self.blinkThresholdView = blinkThresholdView
        
        // Fade Color picker
        let colorPickerItem = NSMenuItem()
        let colorPickerView = MenuColorPickerView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 40),
            title: "Fade Color",
            initialColor: preferencesService.fadeColor
        )
        colorPickerView.onColorChanged = { [weak self] newColor in
            // Use main queue to update preferences to avoid threading issues
            DispatchQueue.main.async {
                self?.preferencesService.fadeColor = newColor
                print("Color picker changed to: \(newColor)")
            }
        }
        
        colorPickerItem.view = colorPickerView
        menu.addItem(colorPickerItem)
        self.colorPickerView = colorPickerView
        
        // Eye Tracking toggle
        let eyeTrackingItem = NSMenuItem(title: "Enable Eye Tracking", action: #selector(toggleEyeTracking), keyEquivalent: "")
        eyeTrackingItem.target = self
        eyeTrackingItem.state = preferencesService.eyeTrackingEnabled ? .on : .off
        menu.addItem(eyeTrackingItem)
    }
    
    @objc private func toggleEyeTracking(_ sender: NSMenuItem) {
        // Toggle the preference
        let newState = !preferencesService.eyeTrackingEnabled
        
        if newState {
            // If turning on, check permissions first
            PermissionsService.shared.checkCameraAccess { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.preferencesService.eyeTrackingEnabled = true
                        sender.state = .on
                    } else {
                        // If permission denied, keep it off
                        self?.preferencesService.eyeTrackingEnabled = false
                        sender.state = .off
                        
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
            preferencesService.eyeTrackingEnabled = false
            sender.state = .off
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
    
    @objc private func openGitHub() {
        NSWorkspace.shared.open(Constants.authorURL)
    }
    
    @objc private func menuWillClose(_ notification: Notification) {
        // If color panel is visible, keep it open
        if NSColorPanel.shared.isVisible {
            // Bring the color panel to the front
            DispatchQueue.main.async {
                NSColorPanel.shared.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// Placeholder for EyeTrackingService that will be implemented later has been removed
// since it's already implemented in BlinkMore/Services/EyeTrackingService.swift 