# Bench tests

Every test below is **not executed**. The app is a port of the Android app; its Dart tests run on a computer and the macOS CI job builds it without signing. It has never run on an iPhone, an iPad or an Apple Watch. Write a result only after a person ran the step.

## What the software already covers (no device needed)

- `python tools/hydra_project_tool.py test` runs the Dart tests (reservations, renewal of the claim, jog dead-man, pairing, command contract).
- The feature contract (`docs/ios_feature_contract.json`) is checked against the Android contract by the CI.

## Setup

- A Mac with Xcode, an iPhone and an iPad with a developer profile, an Apple Watch paired to the iPhone, and the server of a Compute Module or a simulated one reachable from the phone.

## Steps

| # | Step | Expected result | Result |
|---|------|-----------------|--------|
| 1 | Install, open the app and sign in with an operator account, then pair by the `hydra-umc://pair` link. | Login and pairing work as in the Android app. | not executed |
| 2 | Open the 3D view, then send the app to the background and wait one minute. | The page pauses its drawing in the background (battery and heat stay flat) and resumes on return. | not executed |
| 3 | Lock the phone, reopen the app and watch the session and the claim on a robot. | The session survives; the claim is renewed while the Control screen is open and released when the app is closed. | not executed |
| 4 | Hold the jog button and let go, switch app, lock the screen, take a call. | Motion stops at once in every case. | not executed |
| 5 | Turn the Wi-Fi off and on. | The link indicator changes and the controls lock while the link is down. | not executed |
| 6 | Raise an alert on the server. | It reaches the Apple Watch. | not executed |
| 7 | Rotate the iPhone and the iPad, change the text size and the language. | No text is cut, in all eight languages. | not executed |
| 8 | Take the screenshots for the store listing on the iPhone and the iPad. | One set per screen and per language. | not executed |

## What this bench cannot show

Behaviour on older iOS versions, push delivery with the app killed and the effect of low-power mode; list the device and the system version with each result.
