# Initial Sync Module

## Responsibility

Bridge a successful nearby connection into a usable participant album by receiving and persisting the initial album snapshot.

## Behavior

- Present connection and metadata progress instead of an empty album.
- Persist the received album with participant role and connected state.
- Do not download all original assets during initial sync.
- Complete only after an album snapshot has been stored.
- Cancel must stop the nearby session and return to the previous flow.
- Report errors as persistent visible state.

## Navigation

- On completion, the coordinator resets to Album List and then opens Album Detail.
- Do not retain Join Album or Initial Sync in the final back stack.

