# qdot.omashard — OmaShard

Sky: Children of the Light shard eruptions — type, location, and landing times.

An Omarchy shell plugin (bar widget, id `qdot.omashard`). Shows today's shard
in the bar as a color emoji + map name, with a panel for eruption windows and
upcoming days.

## Requirements

- [Omarchy](https://omarchy.org/) (Quickshell shell)
- `python3` (the built-in data fetcher)

## Install

```bash
omarchy plugin install https://github.com/datbuiquoc035/omashard.git
```

## Update

```bash
omarchy plugin update qdot.omashard
```

## Remove

```bash
omarchy plugin remove qdot.omashard
```

## How it works

### Data source

The API (`https://sky-shardfig.plutoy.top/all.json`) is the sole data source,
derived from the original [PlutoyDev/sky-shards](https://github.com/PlutoyDev/sky-shards)
project. It provides daily overrides (realm, map, color, memory, etc.). The
schedule computation (realm rotation, map groups, eruption offsets, DST
handling) is bundled directly in the code — no additional API calls are needed
beyond the override fetch.

### Script: `scripts/fetch_shard_details.py`

Fetches the remote config, applies any day-specific override, and resolves the
shard for a single date. All times are reported in the **local system timezone**
(detected via `datetime.now().astimezone().tzinfo`).

Usage:

```
python3 scripts/fetch_shard_details.py 2026-08-28
```

### Schedule logic: `ShardModel.js`

Pure-JavaScript schedule math used by the QML plugin for preview days. Mirrors
the client-side schedule logic from the sky-shards website.

### Display

- **Bar label**: shows today's shard color emoji + map name (cycles through map / realm / full on right-click)
- **Panel** (left click): today's shard at a glance + eruption windows + upcoming days
- Right-click cycles label format; middle-click force-refreshes
- Auto-refreshes every 30 min; retries on failure; rolls over at midnight

### Caching

The network (API) is hit at most **once per game day**. The script's output is
cached to disk at `~/.local/state/omarchy/qdot.omashard/shards.json` (the same
plain-path convention as the notifications service) and keyed to the game's
home timezone (**midnight America/Los_Angeles**), so the cache resets when the
game day actually rolls over — not at the local midnight.

- On startup the widget loads the cache first and skips the network if it's for
  the current LA game day.
- Middle-click and the IPC `refresh` force a live fetch (which updates the cache).
- If a fetch fails, the last-known-good cached data stays on screen.

## License

MIT — see [LICENSE](LICENSE).
