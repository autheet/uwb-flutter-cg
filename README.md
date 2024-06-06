# Masterthesis

This repository is part of my master's thesis titled **"Design and development
of a platform-independent UWB framework using Flutter"**  at HTWG Konstanz.

_Orginal title: "Entwurf und Entwicklung eines plattformunabhängigen
UWB-Frameworks unter Verwendung von Flutter"_


## Folder structure

- `/flutter_uwb_framework`
    - Source code
    - Setup instructions (how to use)
    - License
- `/measurements`
    - experimental measured data

## Description

With this Flutter plugin it is possible to use the native UWB SDKs of
[Android
Core-Ultrawideband](https://developer.android.com/jetpack/androidx/releases/core-uwb)
and [Apple Nearby
Interaction](https://developer.apple.com/documentation/nearbyinteraction/). It
also integrates out-of-band mechanisms such as [Google Nearby
Connections](https://developers.google.com/nearby/connections/overview) and
[Apple Multipeer
Connectivity](https://developer.apple.com/documentation/multipeerconnectivity)
to find nearby devices and exchange configuration parameters. The aim of the
prototype is to provide a simple starting point to the use of UWB technology
with smartphones. The basic functionalities of both sdks are abstracted
with a standardized interface.

## Features
- Adverties and discover nearby devices
- Receiving UWB data such as distance and direction
- Listening to the different states of the out-of-band mechanism and the UWB session

## License notice

### Qorvo

This software uses parts from the [Qorvo DWM3001CDK Development
Kit](https://www.qorvo.com/products/p/DWM3001CDK) to prototype the usage of
localization and ranging with the DWM3001CDK and Apple Nearby Interaction. This
was used for academic purposes.

### Flutter UWB Plugin

The rest of the software is under MIT license:

Copyright 2024 Christian Greiner

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
