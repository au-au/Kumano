# Create Album Module

## Responsibility

Validate album input, create the local host-owned album record, and hand it to the coordinator.

## Behavior

- Require a trimmed album name between 1 and 60 characters.
- Trip dates remain optional.
- Create the local user as the first member with the host role.
- Persist the album before reporting success.
- Do not start Multipeer Connectivity directly; hosting starts in the invite module.
- After creation, the coordinator replaces this screen with the invite screen so it is not retained in the back stack.

## UI

- Keep the form short and programmatic.
- Hide date controls until enabled.
- Use localized labels and the shared primary button style.

