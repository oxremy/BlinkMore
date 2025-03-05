//
//  PreferencesService.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import Foundation
import SwiftUI
import Combine

class PreferencesService: ObservableObject {
    static let shared = PreferencesService()
    
    private let defaults = UserDefaults.standard
    
    // Initialize with default values
    @Published var fadeSpeed: Double = Constants.defaultFadeSpeed {
        didSet {
            // Normalize to discrete steps (1-5s in steps of 1)
            let normalizedValue = round(fadeSpeed)
            if normalizedValue != fadeSpeed {
                DispatchQueue.main.async {
                    self.fadeSpeed = normalizedValue
                }
            }
        }
    }
    
    @Published var blinkThreshold: Double = Constants.defaultBlinkThreshold {
        didSet {
            // Normalize to discrete steps (3-12s in steps of 1)
            let normalizedValue = round(blinkThreshold)
            if normalizedValue != blinkThreshold {
                DispatchQueue.main.async {
                    self.blinkThreshold = normalizedValue
                }
            }
        }
    }
    
    @Published var fadeColor: NSColor = Constants.defaultFadeColor
    @Published var eyeTrackingEnabled: Bool = Constants.defaultEyeTrackingEnabled
    @Published var hasShownOnboarding: Bool = false
    
    @Published var earSensitivity: Double = Constants.defaultEARSensitivity {
        didSet {
            // Normalize to one of three discrete values (low, medium, high)
            let range = Constants.maxEARSensitivity - Constants.minEARSensitivity
            let step = range / 2.0
            
            var normalizedValue: Double
            let relative = earSensitivity - Constants.minEARSensitivity
            
            if relative < step * 0.5 {
                // Low end - high sensitivity
                normalizedValue = Constants.minEARSensitivity
            } else if relative < step * 1.5 {
                // Middle - medium sensitivity
                normalizedValue = Constants.minEARSensitivity + step
            } else {
                // High end - low sensitivity
                normalizedValue = Constants.maxEARSensitivity
            }
            
            if normalizedValue != earSensitivity {
                DispatchQueue.main.async {
                    self.earSensitivity = normalizedValue
                }
            }
        }
    }
    
    private init() {
        // Load preferences from UserDefaults if they exist
        if let storedFadeSpeed = defaults.object(forKey: Constants.UserDefaultsKeys.fadeSpeed) as? Double {
            fadeSpeed = round(storedFadeSpeed) // Ensure discrete value
        }
        
        if let storedBlinkThreshold = defaults.object(forKey: Constants.UserDefaultsKeys.blinkThreshold) as? Double {
            blinkThreshold = round(storedBlinkThreshold) // Ensure discrete value
        }
        
        // Load color or use default
        if let colorData = defaults.data(forKey: Constants.UserDefaultsKeys.fadeColor),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            fadeColor = color
        }
        
        if let storedEyeTrackingEnabled = defaults.object(forKey: Constants.UserDefaultsKeys.eyeTrackingEnabled) as? Bool {
            eyeTrackingEnabled = storedEyeTrackingEnabled
        }
        
        if let storedHasShownOnboarding = defaults.object(forKey: Constants.UserDefaultsKeys.hasShownOnboarding) as? Bool {
            hasShownOnboarding = storedHasShownOnboarding
        }
        
        if let storedEARSensitivity = defaults.object(forKey: Constants.UserDefaultsKeys.earSensitivity) as? Double {
            // Discretize the stored EAR sensitivity value
            let range = Constants.maxEARSensitivity - Constants.minEARSensitivity
            let step = range / 2.0
            let relative = storedEARSensitivity - Constants.minEARSensitivity
            
            if relative < step * 0.5 {
                earSensitivity = Constants.minEARSensitivity
            } else if relative < step * 1.5 {
                earSensitivity = Constants.minEARSensitivity + step
            } else {
                earSensitivity = Constants.maxEARSensitivity
            }
        }
        
        // Set up property observers
        setupPropertyObservers()
    }
    
    private func setupPropertyObservers() {
        // Add observers to save changes to UserDefaults
        $fadeSpeed
            .dropFirst() // Skip the initial value
            .sink { [weak self] newValue in
                self?.defaults.set(newValue, forKey: Constants.UserDefaultsKeys.fadeSpeed)
            }
            .store(in: &cancellables)
            
        $blinkThreshold
            .dropFirst()
            .sink { [weak self] newValue in
                self?.defaults.set(newValue, forKey: Constants.UserDefaultsKeys.blinkThreshold)
            }
            .store(in: &cancellables)
            
        $fadeColor
            .dropFirst()
            .sink { [weak self] newColor in
                do {
                    let colorData = try NSKeyedArchiver.archivedData(
                        withRootObject: newColor,
                        requiringSecureCoding: false
                    )
                    self?.defaults.set(colorData, forKey: Constants.UserDefaultsKeys.fadeColor)
                    print("Color saved to preferences: \(newColor)")
                } catch {
                    print("Failed to archive color: \(error)")
                }
            }
            .store(in: &cancellables)
            
        $eyeTrackingEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.defaults.set(newValue, forKey: Constants.UserDefaultsKeys.eyeTrackingEnabled)
            }
            .store(in: &cancellables)
            
        $hasShownOnboarding
            .dropFirst()
            .sink { [weak self] newValue in
                self?.defaults.set(newValue, forKey: Constants.UserDefaultsKeys.hasShownOnboarding)
            }
            .store(in: &cancellables)
            
        $earSensitivity
            .dropFirst()
            .sink { [weak self] newValue in
                self?.defaults.set(newValue, forKey: Constants.UserDefaultsKeys.earSensitivity)
            }
            .store(in: &cancellables)
    }
    
    // Add a property to store cancellables
    private var cancellables = Set<AnyCancellable>()
} 