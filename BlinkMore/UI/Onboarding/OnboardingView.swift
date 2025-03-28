//
//  OnboardingView.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject private var preferences = PreferencesService.shared
    @ObservedObject private var permissions = PermissionsService.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "eye")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            Text("Welcome to BlinkMore")
                .font(.system(size: 24, weight: .bold))
            
            Text("BlinkMore helps reduce eye strain by detecting when you're not blinking enough and gently fading the screen as a reminder.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Group {
                Text("This app requires camera access to detect your blinks.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }
            
            Button(action: {
                permissions.requestCameraAccess { granted in
                    DispatchQueue.main.async {
                        preferences.eyeTrackingEnabled = granted
                        preferences.hasShownOnboarding = true
                        isPresented = false
                    }
                }
            }) {
                Text("Continue with Camera Access")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 280)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                preferences.hasShownOnboarding = true
                isPresented = false
            }) {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 20)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// Fixed OnboardingWindowController to avoid @State in a static context
class OnboardingWindowController {
    private var onboardingWindow: NSWindow?
    private var isPresented = true
    private var completion: () -> Void
    
    init(completion: @escaping () -> Void) {
        self.completion = completion
        setupWindow()
    }
    
    private func setupWindow() {
        onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        guard let window = onboardingWindow else { return }
        
        window.center()
        window.title = "Welcome to BlinkMore"
        
        let binding = Binding<Bool>(
            get: { self.isPresented },
            set: { newValue in
                self.isPresented = newValue
                if !newValue {
                    DispatchQueue.main.async {
                        window.close()
                        self.completion()
                    }
                }
            }
        )
        
        let contentView = OnboardingView(isPresented: binding)
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = true
    }
    
    func showWindow() {
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Static convenience method
    static func show(completion: @escaping () -> Void) {
        let controller = OnboardingWindowController(completion: completion)
        controller.showWindow()
    }
} 