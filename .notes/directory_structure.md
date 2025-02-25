# Project Directory Structure

.
├── BlinkMore
│   ├── App
│   │   ├── AppDelegate.swift
│   │   └── BlinkMoreApp.swift
│   ├── Assets.xcassets
│   │   ├── ClosedEyeIcon.imageset
│   │   │   ├── ClosedEyeIcon 1.png
│   │   │   ├── ClosedEyeIcon.png
│   │   │   └── Contents.json
│   │   ├── Contents.json
│   │   └── OpenEyeIcon.imageset
│   │       ├── Contents.json
│   │       ├── OpenEyeIcon 1.png
│   │       └── OpenEyeIcon.png
│   ├── BlinkMore.entitlements
│   ├── Info.plist
│   ├── Preview Content
│   │   └── Preview Assets.xcassets
│   │       └── Contents.json
│   ├── Services
│   │   ├── EyeTrackingService.swift
│   │   ├── FadeService.swift
│   │   ├── PermissionsService.swift
│   │   └── PreferencesService.swift
│   ├── UI
│   │   ├── MenuBar
│   │   │   └── StatusBarController.swift
│   │   ├── Onboarding
│   │   │   └── OnboardingView.swift
│   │   ├── Preferences
│   │   │   ├── PreferencesView.swift
│   │   │   └── PreferencesWindowController.swift
│   │   └── ScreenFade
│   ├── Utilities
│   │   └── Constants.swift
│   └── Vision
├── BlinkMore.xcodeproj
│   ├── project.pbxproj
│   ├── project.xcworkspace
│   │   ├── contents.xcworkspacedata
│   │   ├── xcshareddata
│   │   │   └── swiftpm
│   │   │       └── configuration
│   │   └── xcuserdata
│   │       └── jeremyknox.xcuserdatad
│   │           └── UserInterfaceState.xcuserstate
│   └── xcuserdata
│       └── jeremyknox.xcuserdatad
│           └── xcschemes
│               └── xcschememanagement.plist
├── BlinkMoreTests
│   └── BlinkMoreTests.swift
├── BlinkMoreUITests
│   ├── BlinkMoreUITests.swift
│   └── BlinkMoreUITestsLaunchTests.swift
└── README.md