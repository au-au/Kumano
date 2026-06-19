# Join Album Module

## Responsibility

Allow a participant to discover a nearby hosted album using a four-digit code or QR code, then request connection.

## Code Entry

- Use `.numberPad`.
- Accept exactly four digits, including leading zeroes.
- Strip nonnumeric input and cap the field at four characters.
- Start searching automatically after the fourth digit.
- Do not uppercase, group, or accept letters.

## QR Scanning

- Request camera access only when scanning begins.
- Decode the complete `JoinPayload`.
- Use the code from the payload to run the same nearby-discovery flow as manual entry.
- Stop the capture session after a valid scan or when leaving scan mode.

## Connection

- Keep nearby discovery and invitations in `NearbySessionService`.
- Show durable searching, found, connecting, connected, and error states.
- Notify the coordinator after connection; do not push Initial Sync directly.
- If future collision handling is added for identical four-digit codes, require explicit album selection rather than choosing an arbitrary peer.

