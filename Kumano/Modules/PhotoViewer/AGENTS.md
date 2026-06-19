# Photo Viewer Module

## Responsibility

Display a selected photo or Live Photo, expose metadata, request missing originals, and save complete local assets to Photos.

## Behavior

- Use a black, full-screen presentation.
- Support zoom for still photos.
- Build a `PHLivePhoto` only when both original resources are present.
- Clearly indicate when only a thumbnail is available.
- Enable original download only while connected to the host.
- Enable Save to Photos only when the complete original asset exists.
- Preserve both resources when saving a Live Photo.

## UI

- Keep controls in the system navigation toolbar so iOS 26 receives native Liquid Glass.
- Localize all metadata labels and actions.
- Hide the toolbar when leaving the viewer.
- Keep the viewer rotation-capable even though the rest of the MVP is portrait-first.

