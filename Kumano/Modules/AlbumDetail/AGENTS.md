# Album Detail Module

## Responsibility

Provide the primary shared-album experience: aggregate photos, group them by capture date, filter by contributor, import new assets, request originals, and expose host invite controls.

## Album State

- Treat `NearbySessionService.activeHostedAlbumID` as the source of truth for active host state.
- A stored host album with no active session must display Offline.
- Merge incoming album snapshots by stable member and photo IDs.
- The host rebroadcasts authoritative album updates.
- Persist every accepted metadata or resource change.

## Photo Grid

- Group by local calendar day and sort within each section by capture time.
- Put assets without capture dates in the localized Unknown Date section.
- Keep a compact, borderless, three-column photo grid.
- Show Live Photo and thumbnail-only status without obscuring the image.
- Filtering is contributor-only in the MVP.

## Actions

- All members may add photos through `PhotoLibraryService`.
- Avoid duplicate imports using the available content hash.
- Multi-selection may request missing originals; already-local originals are skipped.
- Host navigation shows `Start Hosting` or `Show Invite`.
- Opening the invite screen replaces Album Detail so Back returns to Album List.
- Do not add delete, edit, tag, map, or comment actions without a scope change.

## Resource Handling

- Store received thumbnails, photos, and paired videos through `AssetStorage`.
- Mark a still photo available after its photo resource arrives.
- Mark a Live Photo available only after both resources exist.
- Host resource requests must target the requesting peer.

