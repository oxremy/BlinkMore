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
    static let maxFadeSpeed: Double = 10.0
    
    static let defaultBlinkThreshold: Double = 5.0 // seconds
    static let minBlinkThreshold: Double = 3.0
    static let maxBlinkThreshold: Double = 10.0
    
    static let defaultFadeColor: NSColor = .black
    static let defaultEyeTrackingEnabled: Bool = false
    
    // UserDefaults keys
    enum UserDefaultsKeys {
        static let fadeSpeed = "fadeSpeed"
        static let blinkThreshold = "blinkThreshold"
        static let fadeColor = "fadeColor"
        static let eyeTrackingEnabled = "eyeTrackingEnabled"
        static let hasShownOnboarding = "hasShownOnboarding"
    }
    
    // Animation constants
    static let fadeInDuration: Double = 1.0 // Will be replaced with user preference
    static let fadeOutDuration: Double = 0.05 // Instant fade out (50ms)
    
    // Eye tracking constants
    static let eyeTrackingFrameRate: Double = 30.0 // frames per second
    static let temporalSmoothingFrameCount: Int = 5 // Number of frames for smoothing
    
    // URLs
    static let authorURL = URL(string: "https://github.com/oxremy")!
} 