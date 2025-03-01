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
    @Published var fadeSpeed: Double = Constants.defaultFadeSpeed
    @Published var blinkThreshold: Double = Constants.defaultBlinkThreshold
    @Published var fadeColor: NSColor = Constants.defaultFadeColor
    @Published var eyeTrackingEnabled: Bool = Constants.defaultEyeTrackingEnabled
    @Published var hasShownOnboarding: Bool = false
    
    private init() {
        // Load preferences from UserDefaults if they exist
        if let storedFadeSpeed = defaults.object(forKey: Constants.UserDefaultsKeys.fadeSpeed) as? Double {
            fadeSpeed = storedFadeSpeed
        }
        
        if let storedBlinkThreshold = defaults.object(forKey: Constants.UserDefaultsKeys.blinkThreshold) as? Double {
            blinkThreshold = storedBlinkThreshold
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
    }
    
    // Add a property to store cancellables
    private var cancellables = Set<AnyCancellable>()
} 