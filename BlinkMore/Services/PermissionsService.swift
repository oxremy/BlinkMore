//
//  PermissionsService.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import Foundation
import AVFoundation
import Combine
import AppKit

class PermissionsService: ObservableObject {
    static let shared = PermissionsService()
    
    @Published var cameraAuthorizationStatus: AVAuthorizationStatus = .notDetermined
    private var pendingCompletions: [(Bool) -> Void] = []
    
    private init() {
        // Initialize with current status
        updateCurrentStatus()
    }
    
    private func updateCurrentStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async { [weak self] in
            self?.cameraAuthorizationStatus = status
        }
    }
    
    func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch currentStatus {
        case .authorized:
            // Already authorized
            DispatchQueue.main.async {
                completion(true)
            }
            return
        case .denied, .restricted:
            // Permission denied or restricted
            DispatchQueue.main.async {
                completion(false)
            }
            return
        case .notDetermined:
            // Need to request permission
            // Add the completion handler to pending list first
            pendingCompletions.append(completion)
            
            // Then request access - this prevents race conditions with multiple simultaneous requests
            if pendingCompletions.count == 1 {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        self?.cameraAuthorizationStatus = granted ? .authorized : .denied
                        
                        // Execute all pending completion handlers
                        self?.pendingCompletions.forEach { $0(granted) }
                        self?.pendingCompletions.removeAll()
                    }
                }
            }
        @unknown default:
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
    
    func checkCameraAccess(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        DispatchQueue.main.async { [weak self] in
            self?.cameraAuthorizationStatus = status
        }
        
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                completion(true)
            }
        case .notDetermined:
            requestCameraAccess(completion: completion)
        case .denied, .restricted:
            DispatchQueue.main.async {
                completion(false)
            }
        @unknown default:
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
    
    func openSystemPreferences() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        
        if NSWorkspace.shared.open(settingsURL) {
            print("Opened System Preferences")
        } else {
            // Fallback to general System Preferences
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
        }
    }
} 