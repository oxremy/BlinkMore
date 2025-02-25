# Project Overview


## Project Goal
Develop a lightweight macOS menu bar application that fades screen to a user-defined color based on two triggers: manual activation or automated eye-tracking. The app runs efficiently in the background, prioritizing minimal resource usage, and an intuitive user experience, while adhering to macOS 12+ compatibility and sandbox guidelines.

---

## Core Functionality

### Dropdown Menu:
- A dropdown menu with three options:
  - **Fade Screen**: Manually triggers a smooth screen fade to a customizable color (default: black) over a configurable duration ("Fade Speed," 1–10 seconds).
    - Toggling off instantly reverts all screens to normal (0.05 seconds).
  - **Preferences**: Opens a settings window to adjust fade speed, fade color, blink threshold, and toggle eye-tracking on/off.
  - **“Made with ❤️ by oxremy”**: Hyperlink button that opens "https://github.com/oxremy" in the default browser.

### Automated Eye-Tracking:
- Uses the system camera (with user consent) for real-time monitoring when enabled via Preferences.
- Processes video using Vision framework (use most common camera frame rate: 30fps).
- Pauses eye-tracking and changes the menu bar icon to closed eye icon if:
  - No user detected.
  - Eyes are not visible.
  - Multiple faces are detected.
- Preprocesses eye regions (resize, normalize to 0–1 range, etc.), caches results, and uses a lightweight Core ML model (e.g. MobileNet-based) to classify eye state: 0 (closed) or 1 (open).
  - (IMPORTANT: Temporary model outputs 0 by default, and every 10 seconds output changes to 1 for 5 seconds.)
  - Applies temporal smoothing to predictions for reliability.
- Triggers a screen fade if eyes remain open beyond a configurable "Blink Threshold" (3–10 seconds), using the Fade Speed duration.
- Fade persists until eyes close, reverting instantly (0.05 seconds).
  - ML model only needs to detect one eye being closed to revert the fade. 


### Menu Bar Icon States:
- Unified icon reflecting app state:
  - Closed Eye (Default): A simple black and white icon that looks like a closed eye.
    - Active unless ML model is detecting an open eye.
  - Open Eye: A simple black and white icon that looks like an open eye.
    - Active when ML model is detecting an open eye.
- Avoids rapid icon toggling during eye-tracking for simplicity.

---

## Key Constraints

- **Resource Efficiency**: Achieved via frame skipping, capped caching, and optimized ML inference frequency, targeting macOS 12+ compatibility.
- **Edge Case Handling**:
  - **No User/Multiple Faces/Eyes Not Visible**: Pauses eye-tracking and use closed eye icon.
  - **Camera Access Denied**: Displays a clear message (e.g., “Enable camera in Settings”) with a button to open System Preferences.
- **UI Simplicity**:
  - Unified icon states for clarity.
  - Onboarding includes camera permission prompt. 
- **Privacy**: No video storage or transmission; camera usage indicated by macOS’s built-in light.
  - First-launch onboarding screen (SwiftUI modal) explaining why the camera is needed (e.g., “This app uses your camera to detect blinks, fading the screen when you stare for too long. Eye lube is the best lube!”). Include a “Grant Access” button that triggers the permission request.
  - If permission is denied, disable eye-tracking in Preferences by default and gray out related options with a tooltip: “Camera access required.” 
  - Document camera usage clearly in the Info.plist and onboarding to avoid user confusion or App Store review issues.

---

## Success Metrics

- Reliable fade activation (manual and ML-driven) with no perceptible lag (<50ms revert time).
- Accurate eye state detection and pause/resume logic for eye-tracking.
- Seamless macOS integration:
  - Sandbox-compliant.
- Low resource footprint (minimal CPU/memory usage under typical conditions).

---

## Technical Notes
- **Implementation**: Built with Swift and SwiftUI for the UI, Vision framework for face/eye detection, and Core ML for eye state classification.
- **Fade Effect**: Uses Core Animation or SwiftUI for smooth transitions, with instant revert bypassing animations.
- **Preferences**: Includes fade speed (1–10s), color picker (default: black), blink threshold (3–10s), and eye-tracking toggle (on/off).