# BlinkMore

BlinkMore is a lightweight macOS menu bar application that helps reduce eye strain by fading your screen to a customizable color when you stare at it for too long without blinking. It uses automated eye-tracking.

## Features

- **Menu Bar App**: Runs efficiently in the background with minimal resource usage
- **Automated Eye-Tracking**: Monitors your blinking patterns and fades the screen automatically
- **Customizable Settings**:
  - Fade Speed: Adjust how quickly the screen fades (1-10 seconds)
  - Fade Color: Choose any color for the screen overlay
  - Blink Threshold: Set how long to wait before triggering a fade (3-10 seconds)
  - Eye-Tracking: Enable/disable automated monitoring

## Requirements

- macOS 12 (Monterey) or later
- Camera access (for eye-tracking feature)

## Installation

1. See Devlopment section below.

On first launch, the app will request camera access if you wish to use the eye-tracking feature.

## Usage

- **Preferences**: Customize fade speed, color, threshold, and toggle eye-tracking

## Privacy

BlinkMore respects your privacy:
- All processing happens locally on your device
- No video is ever stored or transmitted
- The macOS camera indicator light will be on when eye-tracking is active

## Development

To build from source:

1. Clone the repository
2. Open BlinkMore.xcodeproj in Xcode
3. Build and run the project

## License

MIT License

## Credits

Made with ❤️ by [oxremy](https://github.com/oxremy)
