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

// Custom view that can detect mouse events for the "Fade Screen" menu item
class FadeScreenMenuItemView: NSView {
    private var fadeService = FadeService.shared
    private var trackingArea: NSTrackingArea?
    
    // Track state with property observers to minimize redraws
    private var isPressed = false {
        didSet {
            if oldValue != isPressed {
                needsDisplay = true
                
                // Handle state change actions
                if isPressed {
                    fadeService.applyFade()
                } else {
                    fadeService.removeFade()
                }
            }
        }
    }
    
    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }
    
    // Cache for drawing optimization
    private var cachedButtonPath: NSBezierPath?
    private var cachedTextRect: NSRect?
    private var cachedAttributedString: NSAttributedString?
    private var cachedButtonRect: NSRect?
    private var lastBounds: NSRect?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        updateTrackingAreas()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existingTrackingArea = trackingArea {
            removeTrackingArea(existingTrackingArea)
        }
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        isPressed = true
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isPressed = false
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        // If mouse dragged outside the view, consider it a mouse up
        let location = convert(event.locationInWindow, from: nil)
        let wasPressed = isPressed
        isPressed = bounds.contains(location) && wasPressed
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        if isPressed {
            isPressed = false
        }
    }
    
    // Invalidate caches when bounds change
    override var bounds: NSRect {
        didSet {
            if bounds != lastBounds {
                invalidateCaches()
                lastBounds = bounds
            }
        }
    }
    
    // Clear all cached drawing elements
    private func invalidateCaches() {
        cachedButtonPath = nil
        cachedTextRect = nil
        cachedAttributedString = nil
        cachedButtonRect = nil
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Create or reuse cached attributed string
        let attributedString = getCachedAttributedString()
        let stringSize = attributedString.size()
        
        // Create or reuse cached button rect
        let buttonRect = getCachedButtonRect(for: stringSize)
        
        // Create or reuse cached button path
        let buttonPath = getCachedButtonPath(for: buttonRect)
        
        // Set the button background color based on state
        let backgroundColor: NSColor
        if isPressed {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.7)
        } else if isHovered {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9)
        } else {
            backgroundColor = NSColor.controlAccentColor
        }
        
        backgroundColor.setFill()
        buttonPath.fill()
        
        // Create a slight inner shadow when pressed to give depth
        if isPressed {
            NSGraphicsContext.saveGraphicsState()
            let shadowColor = NSColor.black.withAlphaComponent(0.2)
            let shadow = NSShadow()
            shadow.shadowColor = shadowColor
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            shadow.set()
            buttonPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // Add a subtle outer shadow when not pressed
            NSGraphicsContext.saveGraphicsState()
            let shadowColor = NSColor.black.withAlphaComponent(0.2)
            let shadow = NSShadow()
            shadow.shadowColor = shadowColor
            shadow.shadowOffset = NSSize(width: 0, height: 1)
            shadow.shadowBlurRadius = 2
            shadow.set()
            buttonPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        
        // Get cached text rect
        let textRect = getCachedTextRect(for: buttonRect, stringSize: stringSize)
        
        // Adjust text position slightly when pressed to enhance button press effect
        let textDrawRect = isPressed ? 
            NSRect(x: textRect.origin.x, y: textRect.origin.y - 1, width: textRect.width, height: textRect.height) : 
            textRect
        
        attributedString.draw(in: textDrawRect)
    }
    
    // Cache and reuse the attributed string
    private func getCachedAttributedString() -> NSAttributedString {
        if let cached = cachedAttributedString {
            return cached
        }
        
        let labelText = "Fade Screen"
        let labelFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white
        ]
        
        let string = NSAttributedString(string: labelText, attributes: textAttributes)
        cachedAttributedString = string
        return string
    }
    
    // Cache and reuse the button rect
    private func getCachedButtonRect(for stringSize: NSSize) -> NSRect {
        if let cached = cachedButtonRect {
            return cached
        }
        
        let horizontalPadding = 20.0
        let buttonWidth = stringSize.width + (horizontalPadding * 2)
        let centerX = (bounds.width - buttonWidth) / 2
        let rect = NSRect(
            x: centerX,
            y: bounds.origin.y + 2,
            width: buttonWidth,
            height: bounds.height - 4
        )
        
        cachedButtonRect = rect
        return rect
    }
    
    // Cache and reuse the button path
    private func getCachedButtonPath(for buttonRect: NSRect) -> NSBezierPath {
        if let cached = cachedButtonPath {
            return cached
        }
        
        let path = NSBezierPath(roundedRect: buttonRect, xRadius: 6, yRadius: 6)
        cachedButtonPath = path
        return path
    }
    
    // Cache and reuse the text rect
    private func getCachedTextRect(for buttonRect: NSRect, stringSize: NSSize) -> NSRect {
        if let cached = cachedTextRect {
            return cached
        }
        
        let rect = NSRect(
            x: (buttonRect.width - stringSize.width) / 2 + buttonRect.origin.x,
            y: (buttonRect.height - stringSize.height) / 2 + buttonRect.origin.y,
            width: stringSize.width,
            height: stringSize.height
        )
        
        cachedTextRect = rect
        return rect
    }
}

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var fadeScreenCustomMenuItem: NSMenuItem // Changed to store the custom menu item
    private var preferencesService = PreferencesService.shared
    private var fadeService = FadeService.shared
    private var eyeTrackingService: EyeTrackingService?
    
    private var cancelBag = Set<AnyCancellable>()
    
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
        
        // Create custom view for "Fade Screen" menu item
        let customView = FadeScreenMenuItemView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        fadeScreenCustomMenuItem = NSMenuItem()
        fadeScreenCustomMenuItem.view = customView
        menu.addItem(fadeScreenCustomMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Create preferences menu item with larger text
        let preferencesItem = NSMenuItem(title: "", action: #selector(openPreferences), keyEquivalent: ",")
        let preferencesFont = NSFont.systemFont(ofSize: 16, weight: .medium) // Larger font size
        let preferencesAttributes: [NSAttributedString.Key: Any] = [
            .font: preferencesFont,
            .foregroundColor: NSColor.labelColor
        ]
        let preferencesAttributedTitle = NSAttributedString(string: "Preferences", attributes: preferencesAttributes)
        preferencesItem.attributedTitle = preferencesAttributedTitle
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
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
        
        // Subscribe to eye tracking preference changes - optimize with debounce
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
                    
                    // Set closed eye icon
                    if let button = self.statusItem.button {
                        button.image = self.closedEyeImage
                    }
                }
            }
        }
    }
    
    private func setupEyeTrackingObservers() {
        // Optimize eye state monitoring with better Combine operators
        eyeTrackingService?.$isEyeOpen
            .removeDuplicates() // Prevent redundant updates for the same state
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main) // Smooth out rapid state changes
            .receive(on: DispatchQueue.main) // Ensure UI updates happen on main thread
            .sink { [weak self] isOpen in
                guard let self = self else { return }
                
                // Update icon based on eye state - only when needed
                if let button = self.statusItem.button, 
                   button.image != (isOpen ? self.openEyeImage : self.closedEyeImage) {
                    button.image = isOpen ? self.openEyeImage : self.closedEyeImage
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
                            self?.fadeService.applyFade()
                        }
                    }
                    
                    // Store workitem for potential cancellation
                    self.fadeDelayWorkItem = workItem
                    
                    // Schedule the delayed fade
                    DispatchQueue.main.asyncAfter(deadline: .now() + threshold, execute: workItem)
                } else {
                    // Cancel any pending fade
                    self.fadeDelayWorkItem?.cancel()
                    self.fadeDelayWorkItem = nil
                    
                    // Remove fade when eye is closed
                    self.fadeService.removeFade()
                }
            }
            .store(in: &cancelBag)
    }
    
    // Work item for delayed fade action
    private var fadeDelayWorkItem: DispatchWorkItem?
    
    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
    }
    
    @objc private func openGitHub() {
        NSWorkspace.shared.open(Constants.authorURL)
    }
}

// Placeholder for EyeTrackingService that will be implemented later has been removed
// since it's already implemented in BlinkMore/Services/EyeTrackingService.swift 