//
//  AppDelegate.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import Foundation
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var preferencesService = PreferencesService.shared
    private var permissionsService = PermissionsService.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make sure permissions service is initialized first
        _ = PermissionsService.shared
        
        // Initialize status bar controller - but don't start camera access immediately
        statusBarController = StatusBarController()
        
        // Show onboarding for first-time users
        if !preferencesService.hasShownOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboarding()
            }
        } else {
            // If onboarding already completed, verify camera permission status
            verifyPermissions {
                // Only initialize eye tracking after permissions have been verified
                self.statusBarController.initializeEyeTrackingIfEnabled()
            }
        }
    }
    
    private func verifyPermissions(completion: @escaping () -> Void = {}) {
        // Check if eye tracking is enabled but camera permission is not granted
        if preferencesService.eyeTrackingEnabled {
            permissionsService.checkCameraAccess { [weak self] granted in
                if !granted {
                    // Update preferences to disable eye tracking if permissions not granted
                    DispatchQueue.main.async {
                        self?.preferencesService.eyeTrackingEnabled = false
                    }
                }
                
                // Call completion handler regardless of permission state
                DispatchQueue.main.async {
                    completion()
                }
            }
        } else {
            // If eye tracking is not enabled, still call completion
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    private func showOnboarding() {
        OnboardingWindowController.show { [weak self] in
            // Onboarding completed or dismissed
            self?.verifyPermissions {
                // Initialize eye tracking after permissions verified
                self?.statusBarController.initializeEyeTrackingIfEnabled()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up resources if needed
    }
} 