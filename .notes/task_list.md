# Task List 

## 1. Project Setup
- Create a new macOS app project in Xcode targeting macOS 12 and above.
- Configure the project to run as a menu bar application:
  - Update the `Info.plist` to set the application as an agent (no dock icon).
  - Set up the app delegate to initialize a status item in the menu bar.
- Enable sandbox entitlements in the project settings, including camera access.
- Add basic project structure: separate folders for UI, logic, models, and utilities.

## 2. Dropdown Menu Implementation 
- Design the menu bar dropdown:
  - Create an `NSMenu` with three items: "Fade Screen," "Preferences," and "Made with ❤️ by oxremy."
- Implement "Fade Screen":
  - Make it a toggleable menu item (checked/unchecked state).
  - When checked, trigger the screen fade to the user-defined color over the fade speed duration.
  - When unchecked, instantly revert the screen to normal (0.05 seconds).
- Implement "Preferences":
  - Add an action to open a preferences window (see task 3).
- Implement "Made with ❤️ by oxremy":
  - Add an action to open "https://github.com/oxremy" in the default browser using `NSWorkspace`.

## 3. Preferences Window 
- Create a SwiftUI view for the preferences window hosted in an `NSWindow`.
- Add UI components:
  - **Fade Speed Slider**: Slider with range 1–10 seconds, default 5 seconds.
  - **Blink Threshold Slider**: Slider with range 3–10 seconds, default 5 seconds.
  - **Fade Color Picker**: macOS color well, default black.
  - **Eye-Tracking Toggle**: Switch to enable/disable eye-tracking, default off.
- Store settings persistently using `UserDefaults` with keys for each preference.
- Add window management:
  - Open the window from the "Preferences" menu item.
  - Ensure it’s modal or a singleton (only one instance at a time).
  - Add a "Close" button to dismiss the window.

## 4. Screen Fade Effect 
- Research options for a smooth fade display (e.g., SwiftUI views or AppKit windows).
- Implement the fade:
  - Create a full-screen, transparent window for each `NSScreen`.
  - Overlay a SwiftUI view or AppKit view with the user-defined fade color.
  - Animate the opacity from 0 to 1 over the fade speed duration using Core Animation or SwiftUI transitions.
- Implement instant revert:
  - When triggered (manual toggle off or eyes closed), set opacity to 0 immediately (0.05 seconds), bypassing animation.


## 5. Onboarding Screen for Camera Permission 
- Create a SwiftUI modal view for first-launch onboarding.
- Add content:
  - Text: “This app uses your camera to detect blinks and reduce eye strain by fading the screen when you stare for too long. Eye lube is the best lube!”
  - "Grant Access" button to request camera permission via `PermissionsService`.
- Implement permission logic:
  - Use `AVCaptureDevice` (via `PermissionsService`) to request camera access.
  - Store whether onboarding has been shown in `UserDefaults`.
- Handle denial:
  - If denied, disable eye-tracking in preferences (gray out toggle with tooltip: “Camera access required”).
  - Show a message: “Enable camera in Settings” with a button to open System Preferences via `NSWorkspace`.

## 6. Camera Access and Video Capture
- Set up camera access:
  - Add `NSCameraUsageDescription` to `Info.plist`: “Camera used for eye-tracking to fade the screen.”
  - Request permission using `AVCaptureDevice`.
- Configure video capture:
  - Use `AVCaptureSession` to stream video from the front-facing camera at 30 fps.
  - Output frames to a delegate for processing.
- Add start/stop logic:
  - Start the session when eye-tracking is enabled in preferences.
  - Stop the session when eye-tracking is disabled or the app is inactive.

## 7. Face and Eye Detection Using Vision Framework
- Set up Vision pipeline:
  - Create a `VNDetectFaceLandmarksRequest` to process video frames.
  - Extract face bounding boxes and eye landmarks.
- Implement detection logic:
  - Check for exactly one face; pause eye-tracking if zero or multiple faces are detected.
  - Extract left and right eye regions from landmarks.
  - Pause eye-tracking if eye landmarks are not visible (e.g., insufficient confidence).
- Pass eye regions to the next task for classification.

## 8. Eye State Classification with Core ML
- Input: preprocessed eye region images; output: binary classification.
- Acquire Core ML model: (IMPORTANT: Temporary model outputs 0 by default, and every 10 seconds output changes to 1 for 5 seconds.)
  - Use a lightweight model (e.g., MobileNet-based) to classify eye state (0 = closed, 1 = open).
- Preprocess eye regions:
  - Resize to model input size (e.g., 224x224).
  - Normalize pixel values to 0–1 range.
  - Cache preprocessed images with a cap (e.g., 10 frames) to limit memory usage.
- Run inference:
  - Process eye regions with the Core ML model.
  - Apply temporal smoothing (e.g., moving average over 5 frames) to stabilize predictions. Any prediction that is not 0 is considered open.
- Output the smoothed eye state (open/closed) for blink detection.

## 9. Blink Detection and Fade Trigger 
- Track eye state duration:
  - Use a timer to measure how long eyes have been open (state = 1).
  - Reset the timer when eyes close (state = 0).
- Trigger fade:
  - If eyes remain open beyond the blink threshold, activate the screen fade using the fade speed.
  - Maintain the fade until at least one eye closes.
- Revert instantly:
  - When an eye closes (state = 0), revert the screen immediately (0.05 seconds).

## 10. Menu Bar Icon States 
- Design icons:
  - Create simple black-and-white icons: closed eye (default) and open eye.
- Update icon dynamically:
  - Set closed eye when eye-tracking is off, paused, or eyes are closed.
  - Set open eye when eye-tracking is active and eyes are open.
- Prevent rapid toggling:
  - Use debouncing (e.g., 0.5-second delay) to stabilize icon changes based on smoothed eye state.


## 11. Edge Case Handling
- Pause eye-tracking and set closed eye icon when:
  - No face detected.
  - Multiple faces detected.
  - Eyes not visible (e.g., landmarks missing).
- Handle camera access denial:
  - Disable eye-tracking and gray out toggle in preferences.
  - Provide a button in the app to open System Preferences.
- Develop a comprehensive error-handling plan:
  - Implement fallback mechanisms (e.g., disable eye-tracking if camera or ML model fails).
  - Notify users of critical issues (e.g., “Eye-tracking unavailable—check camera settings”).
- Test edge cases:
  - User leaves frame, turns away, or covers camera.
  - Additional scenarios: camera failure, ML model corruption, low-memory conditions.

## 12. Privacy and Security
- Ensure privacy:
  - Process video frames in-memory only; do not store or transmit them.
  - Rely on macOS’s built-in camera light as the usage indicator.
- Document usage:
  - Add to `Info.plist`: `NSCameraUsageDescription` with “Camera used for eye-tracking to detect blinks and reduce eye strain.”
  - Reinforce in UI: Ensure onboarding and preferences clearly state camera usage (e.g., “We use your camera only for blink detection—no recording, no sharing”).
  - Avoid additional logging unless opt-in for debugging.

## 13. Resource Optimization
- Optimize video processing:
  - Implement frame skipping (e.g., process every 2nd or 3rd frame) to reduce CPU load.
  - Cap processing rate if 30 fps is too intensive (e.g., 15 fps with interpolation).
- Optimize ML inference:
  - Run inference only when eye regions change significantly or at a fixed interval (e.g., every 0.1s).
  - Leverage GPU via Core ML’s Metal support if available.
- Manage memory:
  - Limit caching to 10 preprocessed frames.
  - Monitor and cap total memory usage (e.g., <50MB under normal conditions).

## 14. Testing
- Test compatibility:
  - Run on macOS 12, 13, and 14 with single display.
- Test functionality:
  - Verify manual fade toggle and eye-tracking fade under various lighting conditions.
  - Ensure revert time is 0.05 seconds.
- Test efficiency:
  - Measure CPU (<10% average) and memory (<50MB) usage with Activity Monitor.
  - Optimize if metrics exceed targets.
- Test error handling:
  - Simulate edge cases: camera denial, ML model corruption, low-memory conditions.
  - Verify graceful degradation (e.g., eye-tracking disabled with clear user feedback).

## 15. Distribution Preparation
- Verify sandbox compliance:
  - Test with entitlements enabled; ensure no restricted API usage.
- Prepare for App Store (if applicable):
  - Add app icon, screenshots, and description.
  - Submit for review with detailed privacy notes.
- Write documentation:
  - Create a user guide covering setup, preferences, and troubleshooting.

---

## Additional Notes
- **Prioritization**: Start with tasks 1–4 for a functional core app, then add eye-tracking (5–10), and finish with optimization and polish (11–15).
- **Concurrency**: Use `DispatchQueue` for video processing and ML inference to avoid blocking the main thread.
- **Accessibility**: Add accessibility labels to UI elements and test with VoiceOver.
- **Scalability**: Design preferences and UI to support future localization if needed.

