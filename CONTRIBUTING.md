# Contributing to HYDRA-UMC-IOS-CONTROL 📱

## Technology Stack
- **Framework**: Flutter.
- **State**: Provider (`ChangeNotifier`).

## Guidelines
1. **Platform Channels**: Maintain type safety when using `MethodChannel` for native iOS calls.
2. **Safe Area**: Respect the Dynamic Island and bottom notch in all layouts.
3. **I18n**: Update all 7 `.arb` language files in `lib/l10n/` for any new UI text, then regenerate with `flutter gen-l10n`.
