# Bricky

An iOS app that uses AR, computer vision, and AI to scan and identify LEGO pieces in real-time, manage personal brick inventories, suggest builds based on available pieces, and share creations with a community of LEGO builders.

## Features

- **AR Brick Scanning** — Point your camera at LEGO pieces and identify them in real-time using Vision framework detection with confidence scoring and spatial tracking
- **Inventory Management** — Organize scanned pieces by color, category, and dimensions; group pieces into storage bins with physical locations
- **Build Suggestions** — AI-powered engine that recommends buildable projects based on your available inventory with match percentage calculations
- **Minifigure Detection** — Identify and catalog LEGO minifigures by anatomical parts (head, torso, arms, legs, accessories) using Azure AI and CoreML
- **Piece & Set Catalog** — Browse the LEGO piece catalog with set information; track owned sets and completion status
- **Community Sharing** — Post builds with photos, captions, and difficulty ratings; like and comment on others' creations
- **Daily Challenges** — Daily build challenges with completion tracking and timing
- **LiDAR Topographic Rendering** — 3D mesh visualization and pile geometry analysis on compatible devices
- **Photo Scanning** — Scan static images as an alternative to live camera for inventory imports
- **Scan History** — Geo-tagged scan sessions with reverse geocoding
- **Color Calibration** — Camera color calibration wizard for more accurate piece identification

## Tech Stack

| Category | Technologies |
|---|---|
| UI | SwiftUI, NavigationStack |
| AR & Vision | ARKit, Vision, AVFoundation |
| AI & ML | Azure AI Services, CoreML |
| Cloud & Sync | CloudKit, iCloud |
| Sensors | LiDAR, CoreLocation, Camera |
| Subscriptions | StoreKit |

## Requirements

- iOS 17.0+
- Xcode 16+
- Swift 6

## Building

1. Clone the repository
2. Open `Bricky.xcodeproj` in Xcode
3. Select your target device or simulator
4. Build and run (⌘R)

> **Note:** AR and LiDAR features require a physical device. Camera scanning requires a device with a camera.

## Project Structure

```
Bricky/
├── App/            # App entry point, config, root views
├── Camera/         # AR and standard camera managers
├── Extensions/     # Swift extensions and utilities
├── Models/         # Data models (pieces, sets, projects, etc.)
├── Resources/      # Assets, LDraw part library, localization
├── Services/       # Business logic, persistence, API clients
├── ViewModels/     # View models
└── Views/          # SwiftUI views organized by feature
```

## License

All rights reserved.
