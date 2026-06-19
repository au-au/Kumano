# Onboarding Module

## Responsibility

Collect the local user's display name on first launch and persist a stable local profile. This module does not handle accounts, authentication, or permissions.

## Behavior

- Accept a trimmed display name between 1 and 24 characters.
- Enable Continue only when the name is valid.
- Persist a new `UserProfile` through `AppRepository`.
- Request no camera, photo-library, or local-network permissions here.
- Notify `AppCoordinator` through `onComplete`; do not navigate directly.

## UI

- Keep the screen focused on one text field and one primary action.
- Use localized English strings and Dynamic Type.
- Keep Return-key submission equivalent to tapping Continue.

