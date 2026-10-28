# luno_chess

Native Flutter/Dart chess game with cards, AI/local matches, Firebase online
play, progression, cosmetics and social features.

Canonical project status, release identity and verification boundaries:
[Cloud handoff](../DEVAM.md).

Use the Flutter version recorded in the handoff (3.47.1). In the prepared cloud
workspace, activate it with `source /workspace/toolchains/luno-env.sh`; a bundled
Windows SDK is not part of this repository. Run `flutter test` and
`flutter analyze` after changes. Automated tests do not establish live Firebase,
physical-device performance or Google Play acceptance.

The sibling legacy HTML is retained as a visual reference. The production
Android UI is this Flutter project. Online rewards and ranked results remain
server-authoritative. Never bypass App Check or release signing requirements.

## Getting Started

Open this directory in Android Studio and select a phone or emulator.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
