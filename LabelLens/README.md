# LabelLens

An iOS app that reads a product label with the camera and flags ingredients from your avoid list. Everything runs on-device.

## How it works

1. **Capture:** take a photo with the camera or pick one from the library (SwiftUI, PhotosUI, UIKit camera).
2. **On-device OCR:** Apple's Vision framework (`VNRecognizeTextRequest`) extracts the label text.
3. **On-device LLM with tool calling:** Apple's Foundation Models framework turns the OCR text into a typed `LabelReport` (`@Generable`). The model calls the `checkAvoidList` tool, which does the matching in deterministic Swift code.
4. **Output validation:** the app does not trust the model's output as-is.
   - **Grounding check:** ingredients that don't appear in the OCR text are dropped, to catch hallucinations.
   - **Flag check:** flagged items are recomputed in code. Any disagreement with the model is corrected and shown to the user.

## Privacy

There are no network calls. The image, the OCR text and the LLM inference all stay on the device.

## Requirements

- Xcode 26 and iOS 26
- A device with Apple Intelligence enabled, or the simulator on an Apple Intelligence-capable Mac

## Structure

| File | Role |
|---|---|
| `ContentView.swift` | UI and pipeline orchestration |
| `CameraPicker.swift` | Camera capture |
| `TextRecognizer.swift` | Vision OCR |
| `LabelAnalyzer.swift` | Foundation Models session, tool, structured output, validation |

## Demo

![demo](demo.gif)
