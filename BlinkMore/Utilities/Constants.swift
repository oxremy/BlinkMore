//
//  Constants.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import Foundation
import SwiftUI

enum Constants {
    // Default preferences
    static let defaultFadeSpeed: Double = 5.0 // seconds
    static let minFadeSpeed: Double = 1.0
    static let maxFadeSpeed: Double = 5.0
    
    static let defaultBlinkThreshold: Double = 6.0 // seconds
    static let minBlinkThreshold: Double = 3.0
    static let maxBlinkThreshold: Double = 12.0
    
    // EAR sensitivity constants - adjusted for 3 discrete steps
    static let defaultEARSensitivity: Double = 0.16 // medium sensitivity
    static let minEARSensitivity: Double = 0.1 // high sensitivity (lower threshold = more sensitive)
    static let maxEARSensitivity: Double = 0.22 // low sensitivity
    
    static let defaultFadeColor: NSColor = .black
    static let defaultEyeTrackingEnabled: Bool = false
    
    // UserDefaults keys
    enum UserDefaultsKeys {
        static let fadeSpeed = "fadeSpeed"
        static let blinkThreshold = "blinkThreshold"
        static let fadeColor = "fadeColor"
        static let eyeTrackingEnabled = "eyeTrackingEnabled"
        static let hasShownOnboarding = "hasShownOnboarding"
        static let earSensitivity = "earSensitivity"
    }
    
    // Animation constants
    static let fadeInDuration: Double = 1.0 // Will be replaced with user preference
    static let fadeOutDuration: Double = 0.05 // Instant fade out (50ms)
    
    // Timeout constants
    static let fadeTimeoutDuration: Double = 15.0 // Auto-disable eye tracking after 15 seconds of continuous fade
    
    // URLs
    static let authorURL = URL(string: "https://github.com/oxremy")!
} 