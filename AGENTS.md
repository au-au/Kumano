# Kumano Engineering Guide

## Product Scope

Kumano is an iPhone app for nearby collaborative travel-photo albums. A host creates an album and advertises it over Multipeer Connectivity. Up to seven participants join with a four-digit code or QR code. The host keeps the complete assets; participants retain album metadata, thumbnails, and explicitly downloaded originals.

Do not introduce a custom backend, iCloud synchronization, accounts, comments, tags, editing, maps, or remote sharing unless the requested scope explicitly changes.

## Architecture

- Use UIKit with programmatic Auto Layout. Do not add storyboards, XIBs, or SwiftUI screens.
- Follow MVVM. View controllers own layout and user-event forwarding; view models own presentation state and business decisions.
- Use `AppCoordinator` for cross-module navigation. Do not push or present another feature directly from a view model.
- Keep shared models and services in `Kumano/Core`. Feature-specific UI belongs in `Kumano/Modules/<ModuleName>`.
- Depend on service protocols such as `AppRepository`, `AssetStorage`, `PhotoLibraryService`, and `NearbySessionService`, not concrete implementations.
- Keep the minimum deployment target at iOS 16 unless explicitly changed.

## UI and Localization

- Build with the iOS 26 SDK.
- Prefer native Liquid Glass APIs on iOS 26. Put availability checks in the design system when the behavior is reusable.
- Provide a functional UIKit material/button fallback for iOS 16–25. Do not imitate Liquid Glass with custom rendering.
- Use system colors, SF Symbols, Dynamic Type, and a minimum 44-point interaction target.
- Put every user-visible string in the English localization resources. Do not hard-code UI copy in Swift.
- Preserve VoiceOver labels and system accessibility settings when changing controls.

## Nearby Sharing

- A hosting session has one active album, one four-digit numeric code, and one QR payload.
- Reopening the invite screen for the active album must reuse the session and code.
- Generate a new code only after hosting has stopped or another album starts hosting.
- The host is the authoritative album node and complete-asset owner.
- Keep the Multipeer session encrypted with `.required`.
- Respect the eight-device total limit imposed by the MVP.
- Treat disconnects, backgrounding, and partial transfers as recoverable states; never report incomplete assets as available.

## Photo Assets

- Preserve original still-photo resources without re-encoding when possible.
- A Live Photo consists of both its photo and paired-video resources. Do not silently downgrade an incomplete Live Photo to a still image.
- Store durable originals under Application Support and thumbnails through `AssetStorage`.
- Keep metadata paths relative to the asset-storage root.
- Avoid loading original-sized files entirely into memory.

## Project Organization

- Add each new screen or major feature as a first-level group under `Kumano/Modules`.
- Keep module view controller, view model, supporting views, and module-only models together.
- Add reusable UI to `Core/DesignSystem`, not by copying it between modules.
- Update `Kumano.xcodeproj/project.pbxproj` whenever source or localized resource files are added.

## Verification

Run:

```sh
xcodebuild -workspace Kumano.xcworkspace \
  -scheme Kumano \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/KumanoDerived \
  CODE_SIGNING_ALLOWED=NO build
```

Also run `git diff --check` and confirm the app bundle contains no `.storyboardc` or `.nib` files.

