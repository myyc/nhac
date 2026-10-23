# nhac

Flutter Navidrome client (Subsonic API). Desktop (Linux/Windows) playback
uses a custom libmpv FFI player; Android/iOS/macOS use just_audio.

## Cache rules

The local cache (SQLite, cover art, downloaded audio, persisted player
state) is a helper, never ground truth — the server is. When the two
disagree, the cache loses: stale entries are re-resolved or evicted on
the spot, never patched or migrated.

- Never call `NavidromeApi` directly with a cached ID for library data.
  Go through `CacheService`, which re-resolves stale IDs by metadata,
  rewrites the cache row, and evicts entries the server no longer has.
  Any new ID-based server call must follow the same try → heal → evict
  pattern.
- Distinguish "not found" from "network down": Subsonic code 70 is
  `NavidromeApiException.isNotFound` (evict/re-resolve), anything else is
  transient (retry). Never string-match exception text.
- Playback has the equivalent path in `PlayerProvider`: a track that
  fails to load is re-resolved once (server-missing tracks are evicted
  and skipped), and the queue/album cache is remapped to fresh IDs.
- A wholesale ID change (server re-index) is detected by
  `CacheService.verifyCacheIntegrity()` at startup and by the first
  playback recovery; both wipe the cache once and let it re-sync.
- Single server-side deletions are pruned on every successful *full*
  library sync (`pruneLibraryNotIn`): a complete album list is
  authoritative, so cached rows absent from it are evicted. Never prune
  from a truncated/partial fetch.
- Cache writes only ever contain data that just came from the server.

## Playback rules

- Never call a blocking libmpv function (`mpv_command`, `mpv_set_property`,
  `mpv_get_property`, `mpv_wait_event`) from the UI isolate — on Linux that
  isolate is the GTK main thread, so a wedged mpv core freezes the whole
  app. Use `mpv_command_async` (fire-and-forget; property sets go through
  the `set` command). The only blocking calls allowed are init-time ones
  (`mpv_create`/options/`mpv_initialize`) and `mpv_wait_event` inside the
  dedicated event-loop isolate.
- Audio output order on Linux is `pulse,pipewire,alsa`: a PipeWire server
  may silently refuse sandboxed clients (empty registry, handshake never
  completes), and AO init must fail over instead of wedging.
