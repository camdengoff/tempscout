# TempScout for iPhone (native app)

The web version of TempScout can't turn off the iPhone's automatic white balance, so its colour-temperature
readings are only estimates. This native app **locks the camera's white balance (and optionally exposure)**,
so the same card under the same light gives the same pixels every time.

> **Status: stage 1.** Meter (with white balance lock), ND calculator, Library and sun times are here.
> The live camera sun finder is the next stage. The code was written without access to Xcode, so it has not
> been compiled yet; the first build may need small fixes. See "If it doesn't build" below.

## What you need

- A Mac with **Xcode 15 or newer** (free, Mac App Store)
- An iPhone on iOS 16 or newer, and a cable
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to create the Xcode project: `brew install xcodegen`
  (no Homebrew? see "Without XcodeGen" below)

## Build and run

```bash
git clone https://github.com/camdengoff/tempscout.git   # or pull the latest if you already have it
cd tempscout/ios
xcodegen                 # creates TempScout.xcodeproj
open TempScout.xcodeproj
```

In Xcode:

1. Click the **TempScout** project in the left sidebar, choose the **TempScout** target, then **Signing & Capabilities**.
2. Tick **Automatically manage signing** and pick your **Team** (your Apple ID; add it under Xcode ▸ Settings ▸ Accounts if it's not listed).
3. If it complains the bundle ID is taken, change `com.camdengoff.tempscout` to something unique.
4. Plug in your iPhone, choose it as the run destination at the top, press **Run (⌘R)**.
5. On the iPhone: Settings ▸ General ▸ VPN & Device Management ▸ trust your developer certificate, and turn on Developer Mode if asked.

A free Apple ID installs last 7 days, then you re-run from Xcode. A paid developer account ($99/yr) removes that and enables TestFlight.

## Check the maths first (30 seconds)

The colour, calibration, ND and sun maths live in `TempScoutCore`, a plain Swift package. Its tests use numbers
produced by the original web app, so they tell you straight away if the Swift port matches:

```bash
cd ios/TempScoutCore
swift test
```

(or open the folder in Xcode and press ⌘U). All tests should pass. If one fails, tell me which.

## Using it

- The camera starts on the Meter tab. The **padlock** button (bottom left of the panel) locks/unlocks white balance;
  the slider in Settings (the sliders icon) sets which temperature it's locked at. Set it near the light you expect.
- Point the white square at a **white or gray card** in the light you want to measure. The status pill says whether
  the signal is good (too dark / too bright / moving / steady).
- Tap the round shutter to **Measure**: it averages 3 seconds and shows a ± spread. Tap again to resume live.
- **Calibrate** (Settings): measure a light of known Kelvin, type its value, "Add calibration point". Two lights, one warm
  and one cool, give a curve that stays accurate across the range. Redo after changing the white balance lock.
- The ND row under the Kelvin number comes from the ND tab; tap it to edit.

## Without XcodeGen

In Xcode: File ▸ New ▸ Project ▸ iOS ▸ App (SwiftUI, name `TempScout`). Delete the generated `ContentView.swift` and
`TempScoutApp.swift`, drag the `TempScout/` folder's Swift files in, then File ▸ Add Package Dependencies ▸ Add Local ▸
choose `TempScoutCore`. In the target's Info tab add **Privacy - Camera Usage Description** and
**Privacy - Location When In Use Usage Description**.

## If it doesn't build

Copy the red error text from Xcode's Issue navigator and send it to me; fixes are usually one line.

## Layout

```
ios/
  project.yml              XcodeGen project definition
  TempScoutCore/           pure Swift logic + tests (colour maths, calibration, meter engine, ND, sun)
  TempScout/
    Camera/                camera session, white balance / exposure lock, measure-square sampling
    Meter/                 the main screen and its view model
    ND/  Library/  Sun/    the other tabs
```
