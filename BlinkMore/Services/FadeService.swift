//
//  FadeService.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import Foundation
import SwiftUI
import Combine

class FadeService: ObservableObject {
    static let shared = FadeService()
    
    @Published var isFaded: Bool = false
    private var fadeWindows: [NSWindow] = []
    private var preferencesService = PreferencesService.shared
    private var cancellables = Set<AnyCancellable>()
    private var screenChangeDebounceTimer: Timer?
    private let screenChangeDebounceInterval: TimeInterval = 0.5 // Half-second debounce
    
    // Timeout timer for extended fade states
    private var fadeTimeoutTimer: Timer?
    private let fadeTimeoutInterval: TimeInterval = Constants.fadeTimeoutDuration
    
    private init() {
        // Initialize fade windows for each screen
        setupFadeWindows()
        
        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Listen for system wake
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Listen for workspace changes (including fullscreen transitions)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Listen for active application changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Listen for color changes
        preferencesService.$fadeColor
            .dropFirst()
            .sink { [weak self] newColor in
                // If currently faded, update the color immediately
                if self?.isFaded == true {
                    self?.updateFadeColor(newColor)
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
        screenChangeDebounceTimer?.invalidate()
        fadeTimeoutTimer?.invalidate()
    }
    
    @objc private func screensChanged() {
        // Cancel any pending timer
        screenChangeDebounceTimer?.invalidate()
        
        // Start a new debounce timer
        screenChangeDebounceTimer = Timer.scheduledTimer(withTimeInterval: screenChangeDebounceInterval, repeats: false) { [weak self] _ in
            self?.handleScreenChangeDebounced()
        }
    }
    
    private func handleScreenChangeDebounced() {
        // Find the main screen (with built-in camera)
        guard let mainScreen = NSScreen.screens.first else { return }
        
        // Check if we need to recreate the windows
        let needsRecreation = fadeWindows.isEmpty || 
                             (fadeWindows.count == 1 && fadeWindows[0].screen != mainScreen)
        
        if needsRecreation {
            // Save current fade state
            let wasVisible = isFaded
            
            // Recreate the fade window for the main screen
            fadeWindows.forEach { $0.close() }
            fadeWindows.removeAll()
            createFadeWindowForMainScreen()
            
            // Restore fade if it was active
            if wasVisible {
                applyFade(immediately: true)
            }
        } else if isFaded {
            // Just update the existing window's frame if needed
            if let window = fadeWindows.first, window.frame != mainScreen.frame {
                window.setFrame(mainScreen.frame, display: true, animate: false)
            }
        }
    }
    
    private func setupFadeWindows() {
        createFadeWindowForMainScreen()
    }
    
    private func createFadeWindowForMainScreen() {
        // Find the main screen (typically the one with the built-in camera)
        guard let mainScreen = NSScreen.screens.first else { return }
        
        let window = NSWindow(
            contentRect: mainScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: mainScreen
        )
        
        // Configure the window - Set a higher level to ensure visibility
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        
        // Create the fade view with binding to control opacity
        let fadeView = FadeView(opacity: .constant(0.0), color: preferencesService.fadeColor)
        window.contentView = NSHostingView(rootView: fadeView)
        
        fadeWindows.append(window)
    }
    
    func applyFade(immediately: Bool = false) {
        // Remove guard since we want to be able to call this repeatedly while holding
        
        isFaded = true
        
        // Get color and duration from preferences
        let fadeColor = preferencesService.fadeColor
        let fadeDuration = immediately ? 0.1 : preferencesService.fadeSpeed
        
        // First ensure our window is properly positioned before showing
        ensureFadeWindowsAreProperlyPositioned()
        
        fadeWindows.forEach { window in
            // Make sure window is visible first
            if !window.isVisible {
                window.orderFront(nil)
            }
            
            // Force window to be on top of everything
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
            
            // Update the view with new content including animation
            if let hostingView = window.contentView as? NSHostingView<FadeView> {
                let newView = FadeView(
                    opacity: .constant(1.0), 
                    color: fadeColor,
                    animationDuration: fadeDuration
                )
                hostingView.rootView = newView
            }
        }
        
        // Start the timeout timer
        startFadeTimeoutTimer()
        
        // Log the action
        print("Applying fade with color \(fadeColor) and duration \(fadeDuration)")
    }
    
    func removeFade() {
        // Remove guard since we want to be able to call this repeatedly when releasing
        
        isFaded = false
        
        // Cancel timeout timer
        cancelFadeTimeoutTimer()
        
        fadeWindows.forEach { window in
            // Update the view with zero opacity and quick animation
            if let hostingView = window.contentView as? NSHostingView<FadeView> {
                let newView = FadeView(
                    opacity: .constant(0.0), 
                    color: preferencesService.fadeColor,
                    animationDuration: Constants.fadeOutDuration,
                    onAnimationComplete: { [weak self, weak window] in
                        // Only execute when animation is complete
                        guard let self = self, !self.isFaded, let window = window else { return }
                        
                        // Lower window level after animation completes
                        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.normalWindow)) - 1)
                        
                        if window.isVisible {
                            window.orderOut(nil)
                            print("Fade window hidden after animation completed")
                        }
                    }
                )
                hostingView.rootView = newView
            } else {
                // Fallback if hosting view is not available
                print("Warning: Could not access FadeView - forcing window to hide")
                window.alphaValue = 0
                window.orderOut(nil)
            }
        }
        
        print("Removing fade with duration \(Constants.fadeOutDuration)")
    }
    
    private func updateFadeColor(_ color: NSColor) {
        fadeWindows.forEach { window in
            if let hostingView = window.contentView as? NSHostingView<FadeView> {
                // Get the current opacity value
                let currentOpacity = hostingView.rootView.opacity
                
                // Create a new view with current opacity but new color
                let newView = FadeView(
                    opacity: .constant(currentOpacity), 
                    color: color,
                    animationDuration: 0.2 // Short animation for color change
                )
                hostingView.rootView = newView
            }
        }
        
        print("Updated fade color to \(color)")
    }
    
    // Handle system wake events
    @objc private func handleSystemWake() {
        // After wake, verify windows are properly positioned
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // Allow time for screen to fully initialize after wake
            self?.ensureFadeWindowsAreProperlyPositioned()
            
            // If we were faded before sleep, reapply fade
            if self?.isFaded == true {
                self?.applyFade(immediately: true)
            }
        }
    }
    
    // Handle workspace changes (spaces, fullscreen apps)
    @objc private func handleWorkspaceChange() {
        // When spaces change, ensure windows remain at the right level
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            // Ensure proper window level and visibility
            if self.isFaded {
                self.fadeWindows.forEach { window in
                    window.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
                    if !window.isVisible {
                        window.orderFront(nil)
                    }
                }
            }
        }
    }
    
    // Handle app changes
    @objc private func handleAppChange() {
        // Small delay to allow UI to stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            // If faded, ensure windows are still properly positioned and visible
            if self?.isFaded == true {
                self?.ensureFadeWindowsAreProperlyPositioned()
            }
        }
    }
    
    // Ensure windows are properly positioned
    private func ensureFadeWindowsAreProperlyPositioned() {
        // Find the main screen
        guard let mainScreen = NSScreen.screens.first else { return }
        
        if let window = fadeWindows.first {
            // Update window position if needed
            if window.frame != mainScreen.frame {
                window.setFrame(mainScreen.frame, display: true, animate: false)
            }
            
            // NOTE: We can't directly assign to screen property as it's read-only
            // Instead, recreate the window if it's on the wrong screen
            if window.screen != mainScreen {
                // Only recreate if we're not in a faded state
                if !isFaded {
                    // Close old window
                    window.close()
                    fadeWindows.removeFirst()
                    // Create new window on correct screen
                    createFadeWindowForMainScreen()
                }
            }
            
            // If faded, ensure window is visible and at the right level
            if isFaded {
                window.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
                if !window.isVisible {
                    window.orderFront(nil)
                }
            }
        }
    }
    
    // MARK: - Fade Timeout Handling
    
    private func startFadeTimeoutTimer() {
        // Cancel any existing timer first
        cancelFadeTimeoutTimer()
        
        // Create new timer
        fadeTimeoutTimer = Timer.scheduledTimer(withTimeInterval: fadeTimeoutInterval, repeats: false) { [weak self] _ in
            self?.handleFadeTimeout()
        }
        
        print("Started fade timeout timer (\(fadeTimeoutInterval)s)")
    }
    
    private func cancelFadeTimeoutTimer() {
        if let timer = fadeTimeoutTimer, timer.isValid {
            timer.invalidate()
            fadeTimeoutTimer = nil
            print("Cancelled fade timeout timer")
        }
    }
    
    private func handleFadeTimeout() {
        print("Fade timeout reached after \(fadeTimeoutInterval)s - disabling eye tracking")
        
        // Remove fade
        removeFade()
        
        // Disable eye tracking in preferences
        DispatchQueue.main.async {
            self.preferencesService.eyeTrackingEnabled = false
        }
    }
}

// Improved FadeView implementation using proper SwiftUI animation with completion callback
struct FadeView: View {
    @Binding var opacity: Double
    var color: NSColor
    var animationDuration: Double = 1.0
    var onAnimationComplete: (() -> Void)? = nil
    
    var body: some View {
        Color(color)
            .opacity(opacity)
            .edgesIgnoringSafeArea(.all)
            .animation(.easeInOut(duration: animationDuration), value: opacity)
            .onChange(of: opacity) { newValue in
                // If we have a completion handler, call it after animation
                if let completion = onAnimationComplete {
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.05) {
                        completion()
                    }
                }
            }
    }
} 