# Album Invite Module

## Responsibility

This directory is named `HostLobby` in code, but its product-facing meaning is the Album Invite screen. It starts or resumes hosting, displays the four-digit code and QR code, shows connected members, and allows the host to open the album or stop hosting.

## Session Rules

- Starting a new hosting session generates a four-digit numeric code and QR payload.
- Reopening this screen for the currently active album must reuse the existing session, code, token, and connected peers.
- Leaving this screen through Back or Open Album must not stop hosting.
- Only `Stop Hosting` ends the session.
- Stopping and later restarting generates a new code and QR payload.
- Enforce a maximum of seven participant peers.

## Data and Transfers

- Keep the host album synchronized with connected members.
- Persist connection, member, photo, and resource updates through `AppRepository`.
- Relay thumbnails to participants.
- Store incoming photo and paired-video resources through `AssetStorage`.
- Serve requested originals only when the corresponding host resource exists.

## Navigation and UI

- Back must return directly to Album List.
- Open Album must replace this screen with Album Detail; Album Detail then returns to Album List.
- Display the code as exactly four digits without alphabetic formatting.
- Keep QR content based on the full `JoinPayload`, not only the short code.
- Use “Album Invite” terminology in new product copy rather than “Lobby.”

