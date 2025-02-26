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
    private var isPressed = false
    private var isHovered = false
    
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
        fadeService.applyFade()
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isPressed = false
        fadeService.removeFade()
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        // If mouse dragged outside the view, consider it a mouse up
        let location = convert(event.locationInWindow, from: nil)
        let wasPressed = isPressed
        isPressed = bounds.contains(location) && wasPressed
        
        if wasPressed != isPressed {
            needsDisplay = true
            if !isPressed {
                fadeService.removeFade()
            }
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        if isPressed {
            isPressed = false
            fadeService.removeFade()
        }
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw button text first to get its size
        let labelText = "Fade Screen"
        let labelFont = NSFont.systemFont(ofSize: 16, weight: .medium) // Increased to 16pt to match Preferences
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white
        ]
        
        let attributedString = NSAttributedString(string: labelText, attributes: textAttributes)
        let stringSize = attributedString.size()
        
        // Define button appearance properties based on the text size
        let horizontalPadding = 20.0 // Padding on each side of the text
        let buttonWidth = stringSize.width + (horizontalPadding * 2) // Width based on text size plus padding
        let centerX = (bounds.width - buttonWidth) / 2
        let buttonRect = NSRect(
            x: centerX,
            y: bounds.origin.y + 2,
            width: buttonWidth,
            height: bounds.height - 4
        )
        
        // Create button appearance
        let buttonPath = NSBezierPath(roundedRect: buttonRect, xRadius: 6, yRadius: 6)
        
        // Set the button background color based on state
        let backgroundColor: NSColor
        if isPressed {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.7) // Darker when pressed
        } else if isHovered {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9) // Slightly highlighted when hovered
        } else {
            backgroundColor = NSColor.controlAccentColor // Normal state
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
        
        // Center the text in the button
        let textRect = NSRect(
            x: (buttonRect.width - stringSize.width) / 2 + buttonRect.origin.x,
            y: (buttonRect.height - stringSize.height) / 2 + buttonRect.origin.y,
            width: stringSize.width,
            height: stringSize.height
        )
        
        // Adjust text position slightly when pressed to enhance button press effect
        let textDrawRect = isPressed ? 
            NSRect(x: textRect.origin.x, y: textRect.origin.y - 1, width: textRect.width, height: textRect.height) : 
            textRect
        
        attributedString.draw(in: textDrawRect)
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
        
        // Subscribe to eye tracking preference changes
        preferencesService.$eyeTrackingEnabled
            .sink { [weak self] enabled in
                if enabled {
                    self?.initializeEyeTracking()
                } else {
                    self?.eyeTrackingService?.stopTracking()
                    self?.eyeTrackingService = nil
                    // Reset icon to closed eye
                    if let button = self?.statusItem.button {
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
        // Subscribe to eye state changes
        eyeTrackingService?.$isEyeOpen
            .sink { [weak self] isOpen in
                // Update icon based on eye state
                if let button = self?.statusItem.button {
                    button.image = isOpen ? self?.openEyeImage : self?.closedEyeImage
                }
                
                // Trigger fade if eye is open for too long
                if isOpen {
                    let threshold = self?.preferencesService.blinkThreshold ?? Constants.defaultBlinkThreshold
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Int(threshold))) {
                        if self?.eyeTrackingService?.isEyeOpen == true {
                            self?.fadeService.applyFade()
                        }
                    }
                } else {
                    // Remove fade when eye is closed
                    self?.fadeService.removeFade()
                }
            }
            .store(in: &cancelBag)
    }
    
    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
    }
    
    @objc private func openGitHub() {
        NSWorkspace.shared.open(Constants.authorURL)
    }
}

// Placeholder for EyeTrackingService that will be implemented later has been removed
// since it's already implemented in BlinkMore/Services/EyeTrackingService.swift 