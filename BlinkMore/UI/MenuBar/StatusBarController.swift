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
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isPressed = false
        fadeService.removeFade()
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        // If mouse dragged outside the view, consider it a mouse up
        let location = convert(event.locationInWindow, from: nil)
        if !bounds.contains(location) && isPressed {
            isPressed = false
            fadeService.removeFade()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if isPressed {
            isPressed = false
            fadeService.removeFade()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let labelText = "Fade Screen"
        let labelFont = NSFont.menuFont(ofSize: 13)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.labelColor
        ]
        
        let attributedString = NSAttributedString(string: labelText, attributes: textAttributes)
        let stringSize = attributedString.size()
        
        // Center the text vertically and align left with some padding
        let textRect = NSRect(
            x: 20, // Left padding
            y: (bounds.height - stringSize.height) / 2,
            width: bounds.width - 25,
            height: stringSize.height
        )
        
        attributedString.draw(in: textRect)
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
        let customView = FadeScreenMenuItemView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        fadeScreenCustomMenuItem = NSMenuItem()
        fadeScreenCustomMenuItem.view = customView
        menu.addItem(fadeScreenCustomMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let preferencesItem = NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        #if DEBUG
        menu.addItem(NSMenuItem.separator())
        let debugItem = NSMenuItem(title: "Toggle Debug Mode", action: #selector(toggleDebugMode), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)
        #endif
        
        menu.addItem(NSMenuItem.separator())
        
        let creditItem = NSMenuItem(title: "Made with ❤️ by oxremy", action: #selector(openGitHub), keyEquivalent: "")
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
        
        // Subscribe to tracking state for debugging (optional)
        let faceDetectedPublisher = optionalPublisher(eyeTrackingService?.$faceDetected, defaultValue: false)
        let multipleFacesPublisher = optionalPublisher(eyeTrackingService?.$multipleFacesDetected, defaultValue: false)
        let eyesVisiblePublisher = optionalPublisher(eyeTrackingService?.$eyesVisible, defaultValue: false)
        
        Publishers.CombineLatest3(faceDetectedPublisher, multipleFacesPublisher, eyesVisiblePublisher)
            .sink { [weak self] faceDetected, multipleFaces, eyesVisible in
                // We could update the UI based on these states if needed
                print("Face detection status: detected=\(faceDetected), multiple=\(multipleFaces), eyes visible=\(eyesVisible)")
            }
            .store(in: &cancelBag)
    }
    
    // Helper method to handle optional publishers
    private func optionalPublisher<T>(_ publisher: Published<T>.Publisher?, defaultValue: T) -> AnyPublisher<T, Never> {
        if let publisher = publisher {
            return publisher.eraseToAnyPublisher()
        } else {
            return Just(defaultValue).eraseToAnyPublisher()
        }
    }
    
    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
    }
    
    @objc private func openGitHub() {
        NSWorkspace.shared.open(Constants.authorURL)
    }
    
    #if DEBUG
    @objc private func toggleDebugMode() {
        eyeTrackingService?.toggleDebugMode()
    }
    #endif
}

// Placeholder for EyeTrackingService that will be implemented later has been removed
// since it's already implemented in BlinkMore/Services/EyeTrackingService.swift 