# Flutter Plugin for using UWB

dart run pigeon \
  --input uwb-flutter-cg/src/uwb/pigeons/uwb.dart \
  --dart_out uwb-flutter-cg/src/uwb/lib/src/uwb.g.dart \
  --kotlin_out uwb-flutter-cg/src/uwb/android/src/main/kotlin/net/christiangreiner/uwb/Uwb.g.kt \
  --kotlin_package "net.christiangreiner.uwb" \
  --swift_out uwb-flutter-cg/src/uwb/ios/Classes/Uwb.g.swift


### Fork Information: Cross-Platform Refactoring

This version of the plugin represents a significant architectural improvement over the original implementation found in the `masterthesis` repository. The primary goal of these changes was to create a **truly cross-platform and FiRa-compliant** solution for UWB ranging between iOS and Android devices.

The key differences are:

1.  **Unified Discovery via Bluetooth LE:** The original version used separate, platform-specific technologies for device discovery (Apple's Multipeer Connectivity and Google's Nearby Connections). This version replaces both with a **single, unified Bluetooth LE (BLE) implementation** that works across all platforms. This removes a major source of incompatibility and simplifies the native code.
2.  **FiRa-Compliant Handshake:** The UWB configuration and handshake process has been completely refactored. This version now correctly implements the FiRa accessory protocol, where a "Controller" device (e.g., an iPhone) dictates the precise UWB parameters, and the "Accessory" device (e.g., an Android phone) configures itself accordingly. This eliminates the hardcoded parameters and race conditions that caused instability in the original version.
3.  **Simplified Native Plugins:** All BLE logic for discovery and data exchange now resides in the Dart layer. The native iOS and Android plugins are now much simpler, responsible only for interacting with their respective UWB APIs (`NearbyInteraction` and `androidx.core.uwb`).

This refactoring makes the plugin a more robust and reliable foundation for building cross-platform UWB applications.

## Description

This Flutter plugin enables the use of native UWB frameworks: [Android
Core-Ultra Wideband](https://developer.android.com/jetpack/androidx/releases/core-uwb)
and [Apple Nearby
Interaction](https://developer.apple.com/documentation/nearbyinteraction/). It
also integrates out-of-band mechanisms such as [Google Nearby
Connections](https://developers.google.com/nearby/connections/overview) and
[Apple Multipeer
Connectivity](https://developer.apple.com/documentation/multipeerconnectivity)
to find nearby devices and exchange configuration parameters. The aim of the
prototype is to provide a simple starting point for using UWB technology with
smartphones. The basic functionalities of both frameworks are abstracted with a
standardized interface.

## Folder structure

- `/src/uwb`
    - Source code of the uwb flutter package
        - Dart Code: `/src/uwb/lib`
