//
//  BlinkMoreApp.swift
//  BlinkMore
//
//  Created by oxremy on 2/24/25.
//

import SwiftUI

@main
struct BlinkMoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Pre-initialize services to ensure they're ready before UI appears
        _ = PreferencesService.shared
        _ = PermissionsService.shared
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // Disable the automatic Preferences menu item since we handle it in our custom menu
            CommandGroup(replacing: .appSettings) {
                EmptyView()
            }
        }
    }
}
