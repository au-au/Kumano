# Album List Module

## Responsibility

Present all locally known albums, their current role/state, and the primary create, join, open, and host-invite entry points.

## Behavior

- Reload albums from `AppRepository` whenever the screen appears.
- Sort order comes from the repository and reflects most recent activity.
- Tapping a row opens Album Detail.
- Host albums expose an accessory action:
  - `Start Hosting` when no active session exists for that album.
  - `Show Invite` when that album is actively hosted.
- Participant albums must not expose host controls.
- Use `NearbySessionService.activeHostedAlbumID` as the runtime source of truth for active hosting; persisted `.hosting` state alone is insufficient.

## UI

- Keep photos visually dominant and album cards neutral.
- Preserve the bottom Create/Join control group.
- Use the cover thumbnail when available and a system placeholder otherwise.
- Route all actions through coordinator callbacks.

