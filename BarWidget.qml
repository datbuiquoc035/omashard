import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ShardModel.js" as ShardModel

// Bar label for today's Sky shard, and the host for the shard info panel.
//
// Left click reveals the panel (shard color, location, eruption times);
// right click cycles the label format; middle click force-refreshes.
//
// Today's shard is resolved by the bundled fetch_shard_details.py script. The
// remaining preview days use the bundled schedule calculation.
BarWidget {
  id: root
  moduleName: "qdot.omashard"

  // ---- Schedule state --------------------------------------------------
  property var days: []           // computeDays() output for the next few days
  property var todayShard: null   // today's entry (null if none / loading)
  property string fetchError: ""
  property bool loading: true

  readonly property bool vertical: bar ? bar.vertical : false

  // Display timezone as a UTC offset in hours. The schedule math happens on
  // absolute instants, so the label/panel just shift by this. The setting
  // accepts "UTC+n" / "UTC-n", the timezone database name, or a plain
  // numeric offset; empty falls back to the system's own offset.
  readonly property real displayTzOffset: parseTzOffset(setting("timeZone", ""), -new Date().getTimezoneOffset() / 60)

  function parseTzOffset(raw, fallback) {
    var value = String(raw === undefined || raw === null ? "" : raw).trim()
    if (value === "") return fallback
    if (/^UTC\s*[+-]?\d+$/i.test(value)) {
      var numeric = parseFloat(value.replace(/^UTC\s*/i, ""))
      return clampOffset(numeric)
    }
    var parsed = parseFloat(value)
    if (isFinite(parsed)) return clampOffset(parsed)
    return fallback
  }

  function clampOffset(value) {
    if (!isFinite(value)) return 0
    if (value < -14) return -14
    if (value > 14) return 14
    return Math.round(value * 2) / 2
  }

  readonly property string tzLabel: {
    var raw = String(setting("timeZone", "")).trim()
    if (raw === "") return "Local"
    if (/^UTC\s*[+-]?\d+$/i.test(raw)) return raw.toUpperCase()
    var parsed = parseFloat(raw)
    if (isFinite(parsed)) return "UTC" + (parsed >= 0 ? "+" : "") + String(parsed)
    return raw
  }

  // Bar label format: "map", "realm", or "full". Right-click cycles them.
  readonly property string labelMode: setting("format", "map")
  readonly property string nextLabelMode: {
    var modes = ["map", "realm", "full"]
    return modes[(modes.indexOf(labelMode) + 1) % modes.length]
  }

  readonly property int upcomingDays: Math.max(1, Math.min(7, Number(setting("upcomingDays", 3)) || 3))

  function shardLabel() {
    if (!todayShard) return "No shard today"
    var value = todayShard.shardColor === "Red" ? "🔴" : "⚫"
    if (labelMode === "map") return value + " " + todayShard.map
    if (labelMode === "realm") return value + " " + todayShard.realm
    return value + " " + todayShard.map + " · " + todayShard.realm
  }

  readonly property string displayText: shardLabel()

  // ---- Fetching --------------------------------------------------------
  readonly property int fetchIntervalMs: Math.max(60, Number(setting("refreshSeconds", 1800)) || 1800) * 1000

  function todayDateKey() {
    var now = new Date()
    return now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0")
  }

  // Calendar date in the game's home timezone (America/Los_Angeles). The
  // shard schedule resets at midnight LA, so the cache is keyed to that date
  // rather than the local date: the cache stays valid until LA midnight,
  // which is what actually starts a new game day. Reuses the pure-JS LA DST
  // math from ShardModel.js, so no timezone database is needed.
  function laDateKey() {
    var now = new Date()
    var tzMinutes = ShardModel.laOffsetMinutes(
      now.getFullYear(), now.getMonth(), now.getDate(),
      now.getHours(), now.getMinutes()
    )
    // LA wall clock = UTC + offset (offset is negative west of UTC), so the
    // LA date is read from the instant shifted by the offset.
    var laUtc = new Date(now.getTime() + tzMinutes * 60000)
    return laUtc.getUTCFullYear() + "-" +
      String(laUtc.getUTCMonth() + 1).padStart(2, "0") + "-" +
      String(laUtc.getUTCDate()).padStart(2, "0")
  }

  // Quickshell's Process starts in the shell's working directory, not the
  // plugin's, so the script path has to be resolved from this file's own
  // location (the plugin root) rather than given as a bare relative path.
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".")
    var p = url.toString().replace(/^file:\/\//, "")
    if (p.length === 0 || p.charAt(p.length - 1) !== "/") p += "/"
    return p
  }
  readonly property string shardScriptPath: pluginDir + "scripts/fetch_shard_details.py"

  function runShardScript() {
    root.loading = true
    fetchProc.running = false
    fetchProc.workingDirectory = root.pluginDir
    fetchProc.command = ["python3", root.shardScriptPath, root.todayDateKey()]
    fetchProc.running = true
  }

  // Fetch today's data. When forceLive is false, a valid in-memory cache for
  // the current game day (midnight LA) short-circuits the network fetch and
  // the cached payload is used instead. Once the LA date rolls over,
  // cachedLaDate no longer matches and a fresh fetch runs. forceLive always
  // hits the network.
  function fetchData(forceLive) {
    if (forceLive !== true && root.cacheState &&
        root.cachedLaDate === root.laDateKey() && root.cachedPayload) {
      root.settleSchedule(root.cachedPayload)
      return
    }
    root.runShardScript()
  }

  function shardFromScript(payload) {
    if (!payload || payload.has_shard !== true) return null
    if (!payload.realm || !payload.location || !Array.isArray(payload.occurrences)) return null
    return {
      date: payload.date,
      isToday: true,
      realm: payload.realm.name,
      realmKey: payload.realm.id,
      map: payload.location.name,
      mapKey: payload.location.id,
      shardColor: payload.color === "red" ? "Red" : "Black",
      isRed: payload.color === "red",
      rewardAc: payload.rewardAC ? Number(payload.rewardAC) : null,
      variant: Number(payload.variant) || 1,
      occurrences: payload.occurrences.map(function(occurrence) {
        return {
          start: new Date(occurrence.start),
          land: new Date(occurrence.landing),
          end: new Date(occurrence.end),
        }
      }),
    }
  }

  function settleSchedule(payload) {
    root.days = ShardModel.computeDays(root.upcomingDays, {})
    root.todayShard = root.shardFromScript(payload)
    if (root.days.length > 0) root.days[0] = root.todayShard
    root.loading = false
    root.notifyPanel()
  }

  // settleSchedule wrapper that falls back to the last-known-good cached
  // payload when a fetch fails, so the label/panel never blank out. Only
  // falls back when the cache is still for the current game day.
  function settleWithFallback(payload) {
    if (!payload && root.cacheState &&
        root.cachedLaDate === root.laDateKey() && root.cachedPayload) {
      payload = root.cachedPayload
    }
    root.settleSchedule(payload)
  }

  function notifyPanel() {
    if (panelLoader.item && panelLoader.item.onShardsChanged) panelLoader.item.onShardsChanged()
  }

  // Load the persisted cache. If it holds the current game day (midnight
  // LA) we render from it and avoid the network; otherwise a fresh fetch is
  // started. Called once on startup via the cache file's onLoaded/onLoadFailed.
  function loadCache(raw) {
    if (root.cacheDecided) return
    root.cacheDecided = true
    var parsed = null
    try {
      parsed = JSON.parse(String(raw || "").trim())
    } catch (error) {
      parsed = null
    }
    if (parsed && typeof parsed === "object" && parsed.date === root.laDateKey() && parsed.payload) {
      root.cachedLaDate = parsed.date
      root.cachedPayload = parsed.payload
      root.cacheState = true
      root.settleSchedule(parsed.payload)
      return
    }
    root.fetchData()
  }

  property bool cacheDecided: false
  property bool cacheState: false
  property string cachedLaDate: ""
  property var cachedPayload: null
  property var pendingPayload: null

  // Stage a successfully fetched payload to be written to the on-disk cache,
  // keyed to the LA game date so it naturally resets at midnight LA.
  function persistCache(payload) {
    root.pendingPayload = payload
    cacheSaveTimer.restart()
  }

  function flushCache() {
    if (root.pendingPayload === null) return
    root.ensureDir()
    // Write the cache via a Python process rather than FileView.setText.
    // FileView's atomic (temp+rename) write was observed to silently fail to
    // persist for this plugin across shell restarts, while a plain process
    // write lands every time. Passing the JSON as an argv element (not shell
    // interpolation) keeps shard names with apostrophes/quotes safe.
    cacheWriteProc.command = [
      "python3", "-c",
      "import sys, json, os; p=sys.argv[1]; os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'w').write(json.dumps(json.loads(sys.argv[2])))",
      root.cachePath,
      JSON.stringify({ date: root.laDateKey(), payload: root.pendingPayload })
    ]
    cacheWriteProc.running = false
    cacheWriteProc.running = true
  }

  Component.onCompleted: {
    root.ensureDir()
    cacheFile.reload()
  }

  property string lastStderr: ""

  Process {
    id: fetchProc
    command: ["python3", root.shardScriptPath, root.todayDateKey()]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          if (!root.fetchError) root.fetchError = root.lastStderr ? root.lastStderr : "Empty response from shard details script"
          root.settleWithFallback(null)
          return
        }
        var payload = null
        try {
          payload = JSON.parse(raw)
        } catch (error) {
          root.fetchError = "Malformed shard details response"
          root.settleWithFallback(null)
          return
        }
        if (!payload || typeof payload.has_shard !== "boolean") {
          root.fetchError = "Malformed shard details response"
          root.settleWithFallback(null)
          return
        }
        root.fetchError = ""
        root.cachedLaDate = root.laDateKey()
        root.cacheState = true
        root.persistCache(payload)
        root.settleSchedule(payload)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rawErr = String(text || "").trim()
        if (rawErr) {
          var match = rawErr.match(/Error:\s*(.*)/i)
          root.lastStderr = match ? match[1] : rawErr
        } else {
          root.lastStderr = ""
        }
      }
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) {
        if (!root.fetchError) {
          root.fetchError = root.lastStderr ? root.lastStderr : "Shard details script failed"
        }
        root.settleWithFallback(null)
      }
    }
  }

  // ---- Daily on-disk cache -------------------------------------------------
  // Persist today's (LA game day) payload so the network is hit at most once
  // per day, across shell restarts. Keyed to midnight America/Los_Angeles,
  // which is when the game day actually resets.
  //
  // Uses an explicit plain path under ~/.local/state/omarchy (the same
  // convention as the notifications service). The cache is read back with a
  // FileView, but written through a python Process: FileView's atomic
  // temp+rename write was observed to silently not persist here, while a
  // process write lands reliably.
  readonly property string home: Quickshell.env("HOME")
  readonly property string cacheDir: home + "/.local/state/omarchy/qdot.omashard"
  readonly property string cachePath: root.cacheDir + "/shards.json"

  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.cacheDir]
    running: false
  }

  Process {
    id: cacheWriteProc
    command: []
    running: false
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadCache(text())
    onLoadFailed: root.loadCache("")
  }

  Timer {
    id: cacheSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushCache()
  }

  function ensureDir() {
    ensureDirsProc.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.fetchIntervalMs
    repeat: true
    running: root.cacheDecided
    onTriggered: root.fetchData()
  }

  // When the script fails, retry every minute until it answers; the moment a
  // fetch succeeds the error clears and this stops. Retries force a live
  // fetch so a stale-but-valid cache doesn't swallow the retry.
  Timer {
    id: retryTimer
    interval: 60000
    repeat: true
    running: root.fetchError !== "" && !root.loading
    onTriggered: root.fetchData(true)
  }

  // Roll over at midnight: label and panel should follow the calendar date
  // even if a fetch is slow.
  SystemClock {
    id: clock
    precision: SystemClock.Hours
    onDateChanged: root.fetchData()
  }

  // ---- Panel hosting. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    root.fetchData()
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property real openPanelIndicatorWidth: root.vertical ? root.iconSize : Math.max(Style.space(12), barTextLabel.implicitWidth + root.iconSize + Style.spaceReal(6))
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function cycleLabelMode() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry["format"] = root.nextLabelMode
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Logo size suited to the bar: smaller of the bar height and a comfortable
  // body-text cap, so it never overruns a horizontal bar's slot.
  readonly property real iconSize: Math.round(
    Math.min(root.vertical ? (bar ? bar.barSize : 0) : 100, Style.font.body * 1.6)
  )

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "qdot.omashard"

    function refresh(): void { root.fetchData(true) }
    function cycleFormat(): void { root.cycleLabelMode() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // Off-screen twin of the bar label so the laid-out width can be measured
  // before the button's contents exist (an anchored child does not
  // contribute to implicit size).
  Text {
    id: measureText
    visible: false
    text: root.displayText
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? root.barSize : Math.ceil(root.iconSize + Style.spaceReal(6) + measureText.implicitWidth)
    fixedHeight: root.vertical ? root.barSize : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.todayShard
      ? (root.todayShard.shardColor + " shard at " + root.todayShard.map + " (" + root.todayShard.realm + ")")
      : "No shard landing today"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleLabelMode()
      else if (b === Qt.MiddleButton) root.fetchData(true)
      else root.togglePanel()
    }

    Row {
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.spaceReal(6)

      Image {
        id: barIcon
        anchors.verticalCenter: parent.verticalCenter
        source: Qt.resolvedUrl("assets/tgc-logo.png")
        width: root.iconSize
        height: root.iconSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        sourceSize.width: Math.round(root.iconSize * (Screen.devicePixelRatio || 1))
        sourceSize.height: Math.round(root.iconSize * (Screen.devicePixelRatio || 1))
        opacity: root.loading ? 0.6 : 1.0
      }

      Text {
        id: barTextLabel
        text: root.displayText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        opacity: root.todayShard ? 1.0 : 0.6
      }
    }

    Column {
      visible: root.vertical
      anchors.centerIn: parent

      Image {
        source: Qt.resolvedUrl("assets/tgc-logo.png")
        width: root.iconSize
        height: root.iconSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        sourceSize.width: Math.round(root.iconSize * (Screen.devicePixelRatio || 1))
        sourceSize.height: Math.round(root.iconSize * (Screen.devicePixelRatio || 1))
        opacity: root.loading ? 0.6 : 1.0
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.todayShard ? (root.todayShard.shardColor === "Red" ? "🔴" : "⚫") : ""
        color: button.foreground
        font.pixelSize: Style.font.caption
      }
    }
  }
}
