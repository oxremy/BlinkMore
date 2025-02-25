//
//  PreferencesWindowController.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import Foundation
import SwiftUI
import AppKit

class PreferencesWindowController: NSWindowController {
    // Singleton instance
    static let shared = PreferencesWindowController()
    
    convenience init() {
        // Create the preferences window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "BlinkMore Preferences"
        window.contentView = NSHostingView(rootView: PreferencesView())
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
} 