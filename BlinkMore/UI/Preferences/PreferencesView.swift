//
//  PreferencesView.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import SwiftUI
import Combine
import AppKit

struct PreferencesView: View {
    @ObservedObject private var preferences = PreferencesService.shared
    @ObservedObject private var permissions = PermissionsService.shared
    
    @State private var selectedColor: Color = Color(PreferencesService.shared.fadeColor)
    @State private var eyeTrackingEnabled: Bool = PreferencesService.shared.eyeTrackingEnabled
    
    private var isCameraAccessDenied: Bool {
        permissions.cameraAuthorizationStatus == .denied || permissions.cameraAuthorizationStatus == .restricted
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Fade Speed Slider
            VStack(alignment: .leading) {
                Text("Fade Speed: \(Int(preferences.fadeSpeed)) seconds")
                    .font(.subheadline)
                
                HStack {
                    Text("\(Int(Constants.minFadeSpeed))")
                    Slider(value: $preferences.fadeSpeed, in: Constants.minFadeSpeed...Constants.maxFadeSpeed, step: 1)
                    Text("\(Int(Constants.maxFadeSpeed))")
                }
            }
            
            // Blink Threshold Slider
            VStack(alignment: .leading) {
                Text("Blink Threshold: \(Int(preferences.blinkThreshold)) seconds")
                    .font(.subheadline)
                
                HStack {
                    Text("\(Int(Constants.minBlinkThreshold))")
                    Slider(value: $preferences.blinkThreshold, in: Constants.minBlinkThreshold...Constants.maxBlinkThreshold, step: 1)
                    Text("\(Int(Constants.maxBlinkThreshold))")
                }
            }
            
            // Fade Color Picker
            VStack(alignment: .leading) {
                Text("Fade Color")
                    .font(.subheadline)
                
                ColorPicker("Select Fade Color", selection: $selectedColor)
                    .labelsHidden()
                    .onChange(of: selectedColor) { newValue in
                        preferences.fadeColor = NSColor(newValue)
                    }
            }
            
            // Eye Tracking Toggle
            VStack(alignment: .leading) {
                Toggle("Enable Eye Tracking", isOn: $eyeTrackingEnabled)
                    .disabled(isCameraAccessDenied)
                    .onChange(of: eyeTrackingEnabled) { newValue in
                        if newValue {
                            permissions.checkCameraAccess { granted in
                                DispatchQueue.main.async {
                                    if granted {
                                        preferences.eyeTrackingEnabled = true
                                    } else {
                                        eyeTrackingEnabled = false
                                        preferences.eyeTrackingEnabled = false
                                    }
                                }
                            }
                        } else {
                            preferences.eyeTrackingEnabled = false
                        }
                    }
                
                if isCameraAccessDenied {
                    HStack {
                        Text("Camera access required for eye tracking")
                            .font(.caption)
                            .foregroundColor(.red)
                        
                        Button("Open Settings") {
                            permissions.openSystemPreferences()
                        }
                        .font(.caption)
                    }
                }
            }
            
            Spacer()
            
            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    preferences.resetToDefaults()
                    selectedColor = Color(preferences.fadeColor)
                    eyeTrackingEnabled = preferences.eyeTrackingEnabled
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            selectedColor = Color(preferences.fadeColor)
            eyeTrackingEnabled = preferences.eyeTrackingEnabled
        }
    }
} 