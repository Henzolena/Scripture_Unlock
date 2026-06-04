# Scripture_Unlock Xcode Project Structure

## Root Directory
```
Scripture_Unlock/
├── .DS_Store
├── .git/
├── Scripture_Unlock/              # Main app source code
├── Scripture_Unlock.xcodeproj/    # Xcode project configuration
├── Scripture_UnlockTests/         # Unit tests
└── Scripture_UnlockUITests/       # UI tests
```

## Main App Source (Scripture_Unlock/)
```
Scripture_Unlock/
├── .DS_Store
├── Assets.xcassets/               # App assets (images, colors, icons)
│   ├── AccentColor.colorset/
│   ├── AppIcon.appiconset/
│   └── Contents.json
├── ContentView.swift              # Main view
└── Scripture_UnlockApp.swift      # App entry point
```

## Xcode Project Configuration (Scripture_Unlock.xcodeproj/)
```
Scripture_Unlock.xcodeproj/
├── project.pbxproj                # Project file (build settings, targets, file references)
├── project.xcworkspace/           # Workspace configuration
│   ├── contents.xcworkspacedata
│   ├── xcshareddata/
│   └── xcuserdata/
└── xcuserdata/                     # User-specific project data
    └── henokrobale.xcuserdatad/
```

## Unit Tests (Scripture_UnlockTests/)
```
Scripture_UnlockTests/
└── Scripture_UnlockTests.swift    # Unit test cases
```

## UI Tests (Scripture_UnlockUITests/)
```
Scripture_UnlockUITests/
├── Scripture_UnlockUITests.swift          # UI test cases
└── Scripture_UnlockUITestsLaunchTests.swift  # App launch UI tests
```

## Project Type
- **Platform**: iOS
- **Language**: Swift
- **UI Framework**: SwiftUI (inferred from ContentView.swift)
- **Architecture**: Standard iOS app structure with separate test targets

## Key Files
- `Scripture_UnlockApp.swift` - App lifecycle and entry point
- `ContentView.swift` - Primary view for the app
- `project.pbxproj` - Contains all project configuration, build settings, and file references
