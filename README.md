# qdot.omashard — OmaShard

Sky: Children of the Light shard eruptions — type, location, and landing times.

## Structure

```
qdot.omashard/
├── manifest.json                  # Omarchy plugin manifest (id: qdot.omashard)
├── BarWidget.qml                  # Bar widget — fetches today's shard, shows label + panel
├── Panel.qml                      # Shard info popup (today + upcoming eruptions)
├── ShardModel.js                  # Pure schedule math (no dependencies)
├── Subtitles.js                   # Rotating subtitle lines for the panel
├── assets/
│   └── tgc-logo.png               # Sky-shards logo
├── scripts/
│   └── fetch_shard_details.py     # Python script: fetches live overrides + computes schedule
└── README.md                      # This file
```

## How it works

### Data source
The **API** (`https://sky-shardfig.plutoy.top/all.json`) is the sole data source.
It provides daily overrides (realm, map, color, memory, etc.).
The schedule computation (realm rotation, map groups, eruption offsets, DST handling)
is bundled directly in the code — no additional API calls are needed beyond the override fetch.

### Script: `scripts/fetch_shard_details.py`
Fetches the remote config, applies any day-specific override, and resolves the shard
for a single date. All times are reported in the **local system timezone**
(detected via `datetime.now().astimezone().tzinfo`).

Usage:
```
python3 scripts/fetch_shard_details.py 2026-08-28
```

### Schedule logic: `ShardModel.js`
Pure-JavaScript schedule math used by the QML plugin for preview days.
Mirrors the client-side schedule logic from the sky-shards website.

### Display
- **Bar label**: shows today's shard color emoji + map name (cycles through map / realm / full on right-click)
- **Panel** (left click): today's shard at a glance + eruption windows + upcoming days
- Right-click cycles label format; middle-click force-refreshes
- Auto-refreshes every 30 min; retries on failure; rolls over at midnight
