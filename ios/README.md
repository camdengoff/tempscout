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

There are three measuring modes (Settings ▸ Measuring mode). **Scene is the default and needs no setup.**

- **Scene:** just point the phone at the light or the scene. It shows the colour temperature the camera's own automatic
  white balance estimates, like most colour-temperature apps.
- **Card:** more precise for one light. Fill the white square with a **white or gray card** in that light. The app adjusts
  the camera's white balance until the card looks neutral, then reads the temperature from Apple's own factory calibration
  of your camera.
- **Manual:** advanced. Lock white balance yourself (padlock, slider in Settings) and calibrate against known lights.

For all modes:

- Wait for the pill to say "Steady", then tap the round shutter to **Measure**: it averages 3 seconds and shows a ± spread.
  Tap again to resume live.
- Exposure automatically follows the white square (and freezes during a Measure).
- **Calibrate (optional):** if a light whose colour you know reads off, Measure it, type its Kelvin in Settings ▸ Calibrate
  and add it. Each mode keeps its own calibration points.
- The ND row under the Kelvin number shows your plan from the ND tab (ND, shutter, ISO, f-stop); tap it to edit.

## ND tab: frame the shot and preview the exposure

The ND tab shows the live camera with another camera's frame drawn over it, and previews the exposure with your ND filter.

- **Frame:** pick a camera (ARRI, RED, Sony, Canon, Blackmagic, Super 35, Micro 4/3, 1-inch, and more, or your own under
  Custom), a lens focal length and a frame shape (16:9, 2.39:1, 4:3, 9:16…). The frame is drawn at its true size over the live
  picture, with the field of view in degrees and the full-frame equivalent. "Zoom to fill" zooms the phone so the frame fills
  the screen. The phone's own lens limits what it can show (roughly 26mm to 120mm full-frame equivalent on the main camera).
- **Exposure:** set frame rate, shutter angle, ISO and f-stop, then choose an ND filter (or Auto). The app reads the scene's
  brightness from the phone's own auto exposure, shows how many stops over or under your settings would expose it, tells you how
  much ND the scene needs, and brightens or darkens the live picture to preview it.
- The scene brightness assumes the metered area is middle grey (like any reflected light meter), so a very bright or very dark
  scene reads a little off. Treat the preview as a guide, not a measurement.
- Camera recording areas are approximate and differ by shooting mode; use Custom for exact numbers.
- After pulling new code, run `xcodegen` again in `ios/` so Xcode picks up added and removed files.

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
