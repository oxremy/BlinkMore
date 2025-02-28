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
    }
    
    @objc private func screensChanged() {
        // Recreate fade windows when screen configuration changes
        fadeWindows.forEach { $0.close() }
        fadeWindows.removeAll()
        setupFadeWindows()
        
        // If currently faded, apply fade to new screens
        if isFaded {
            applyFade(immediately: true)
        }
    }
    
    private func setupFadeWindows() {
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
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
    }
    
    func applyFade(immediately: Bool = false) {
        // Remove guard since we want to be able to call this repeatedly while holding
        
        isFaded = true
        
        // Get color and duration from preferences
        let fadeColor = preferencesService.fadeColor
        let fadeDuration = immediately ? 0.1 : preferencesService.fadeSpeed
        
        fadeWindows.forEach { window in
            // Make sure window is visible first
            if !window.isVisible {
                window.orderFront(nil)
            }
            
            // Force window to be on top
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
        
        print("Applying fade with color \(fadeColor) and duration \(fadeDuration)")
    }
    
    func removeFade() {
        // Remove guard since we want to be able to call this repeatedly when releasing
        
        isFaded = false
        
        fadeWindows.forEach { window in
            // Update the view with zero opacity and quick animation
            if let hostingView = window.contentView as? NSHostingView<FadeView> {
                let newView = FadeView(
                    opacity: .constant(0.0), 
                    color: preferencesService.fadeColor,
                    animationDuration: Constants.fadeOutDuration
                )
                hostingView.rootView = newView
                
                // Immediately update the window level to ensure it goes behind other windows
                window.level = NSWindow.Level(Int(CGWindowLevelForKey(.normalWindow)) - 1)
                
                // Hide window after animation completes - use a shorter delay to ensure responsiveness
                DispatchQueue.main.asyncAfter(deadline: .now() + Constants.fadeOutDuration + 0.01) { [weak self, weak window] in
                    // Only hide if we're still in not-faded state
                    guard let self = self, !self.isFaded, let window = window else { return }
                    
                    if window.isVisible {
                        window.orderOut(nil)
                        print("Fade window hidden after animation completed")
                    }
                }
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
}

// Improved FadeView implementation using proper SwiftUI animation
struct FadeView: View {
    @Binding var opacity: Double
    var color: NSColor
    var animationDuration: Double = 1.0
    
    var body: some View {
        Color(color)
            .opacity(opacity)
            .edgesIgnoringSafeArea(.all)
            .animation(.easeInOut(duration: animationDuration), value: opacity)
    }
} 