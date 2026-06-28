# Settings Module

## Responsibility

Present personal information and app settings owned by the local user.

## Behavior

- Load and save the local profile through `AppRepository`.
- Preserve the existing `memberID` when the display name changes.
- Keep display names between 1 and 24 non-whitespace characters.
- Route dismissal through the coordinator callback.

## UI

- Use an inset-grouped system settings layout.
- Keep personal information separate from future system settings sections.
- Preserve Dynamic Type, VoiceOver labels, and native text-input behavior.
