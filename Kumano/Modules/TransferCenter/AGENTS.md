# Transfer Center Module

## Responsibility

Present persisted upload and download task state grouped by lifecycle status.

## Behavior

- Read tasks through `AppRepository`.
- Group active uploads, active downloads, waiting, failed, and completed tasks.
- Omit empty sections.
- Display direction, peer, and progress clearly.
- Retry and cancel behavior must update the underlying transfer coordinator/repository before changing UI state.
- Do not create a permanent top-level tab or navigation destination for this module.

## UI

- Keep the screen a simple inset-grouped table.
- Use localized section titles and SF Symbols.
- Preserve task state after leaving and reopening the screen.

