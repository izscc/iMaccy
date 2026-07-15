# Development and Regression Testing

## Prerequisites

Use a complete Xcode installation, not Command Line Tools only:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

## Repeatable Commands

Full macOS test plan:

```bash
xcodebuild test \
  -project iMaccy.xcodeproj \
  -scheme iMaccy \
  -destination 'platform=macOS'
```

Window and activation regression tests:

```bash
xcodebuild test \
  -project iMaccy.xcodeproj \
  -scheme iMaccy \
  -destination 'platform=macOS' \
  -only-testing:iMaccyTests/WindowDismissalPolicyTests \
  -only-testing:iMaccyTests/ItemActionCoordinatorTests \
  -only-testing:iMaccyUITests/MaccyUITests/testPopupWithHotkey \
  -only-testing:iMaccyUITests/MaccyUITests/testPromptCreateEditAndCopyFlow
```

Prompt correctness and performance tests:

```bash
xcodebuild test \
  -project iMaccy.xcodeproj \
  -scheme iMaccy \
  -destination 'platform=macOS' \
  -only-testing:iMaccyTests/PromptIntegrityTests \
  -only-testing:iMaccyTests/PromptSearchParserTests \
  -only-testing:iMaccyTests/PromptSnapshotTests \
  -only-testing:iMaccyTests/PromptEditorTests \
  -only-testing:iMaccyTests/PromptSelectionTests
```

## Signposts

Record the `in.zscc.iMaccy` / `Performance` category in Instruments using the Points of Interest template. The app emits intervals or events for cold launch, first popup, History load/search/add, Prompt load/search, and bulk tag operations.

Diagnostics never include History titles or Prompt bodies. Debug paste logging records allow-listed event names only.

## Manual Window Matrix

Verify hotkey and status-item opening against desktop, another app, an owned sheet, context menu, popover, and the character picker. For both History and Prompt, verify keyboard and pointer paste return to the original text field. A Prompt inspector Copy action must leave the panel open and must not synthesize paste.

## Current Baseline Limitation

On 2026-07-16 the development machine exposed only `/Library/Developer/CommandLineTools`; `xcodebuild` and SwiftLint could not run. Swift syntax parsing, focused pure-Swift type checks, project/plist validation, localization validation, and whitespace checks were used until a complete Xcode installation is available.
