import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "ShardModel.js" as ShardModel
import "Subtitles.js" as Subtitles

// The shard info popup: a title card (logo + name + a rotating subtitle),
// today's shard at a glance, and the eruption windows for the next few
// days. Owned by BarWidget.qml, which hands this panel the button to
// anchor against and keeps the schedule data fresh.
Panel {
  id: root
  moduleName: "qdot.omashard"
  ipcTarget: "qdot.omashard"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Shared with the host widget: the computed schedule and today's entry.
  property var days: hostWidget ? hostWidget.days : []
  property var todayShard: hostWidget ? hostWidget.todayShard : null
  property string fetchError: hostWidget ? hostWidget.fetchError : ""
  property bool loading: hostWidget ? hostWidget.loading : true
  readonly property real displayTzOffset: hostWidget ? hostWidget.displayTzOffset : 0
  readonly property string tzLabel: hostWidget ? hostWidget.tzLabel : "Local"
  readonly property int upcomingCount: Math.max(1, Math.min(7, Number(setting("upcomingDays", 3)) || 3))

  // A subtitle is picked when the panel opens or the data rolls over, so a
  // long-lived panel does not sit on one line forever.
  property string subtitle: Subtitles.getRandomSubtitle()

  // GUARDED so the widget renders before the bar is injected (the
  // bar-widget contract instantiates this bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color redColor: Color.accent
  readonly property color blackColor: contentForeground

  function open() {
    refresh(false)
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Called by the host whenever the schedule data changes.
  function onShardsChanged() {
    root.days = hostWidget ? hostWidget.days : []
    root.todayShard = hostWidget ? hostWidget.todayShard : null
    root.fetchError = hostWidget ? hostWidget.fetchError : ""
    root.loading = hostWidget ? hostWidget.loading : true
  }

  function refresh(forceSubtitle) {
    if (forceSubtitle || !root.opened) root.subtitle = Subtitles.getRandomSubtitle()
    if (hostWidget && hostWidget.fetchData) hostWidget.fetchData()
  }

  // ---- Display helpers ------------------------------------------------
  function colorDot(color) {
    return color === "Red" ? "🔴" : "⚫"
  }

  function occurrenceSummary(occ) {
    if (!occ) return ""
    return ShardModel.formatTime(occ.start, root.displayTzOffset)
      + " → " + ShardModel.formatTime(occ.land, root.displayTzOffset)
      + " → " + ShardModel.formatTime(occ.end, root.displayTzOffset)
  }

  // Weekday label for a yyyy-MM-dd date key, or "Tomorrow" for the next day.
  function dayLabel(dateKey, isNext) {
    if (isNext) return "TOMORROW"
    var parts = String(dateKey).split("-")
    if (parts.length !== 3) return dateKey
    var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    var names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    return names[d.getDay()]
  }

  // Non-null shards after today, in order, capped at upcomingCount.
  function upcomingShards() {
    var out = []
    for (var i = 1; i < root.days.length; i++) {
      if (!root.days[i]) continue
      out.push(root.days[i])
      if (out.length >= root.upcomingCount) break
    }
    return out
  }

  readonly property var nextShard: upcomingShards().length > 0 ? upcomingShards()[0] : null

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (hostWidget && hostWidget.settleSchedule) hostWidget.settleSchedule(null)
      root.subtitle = Subtitles.getRandomSubtitle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(infoColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: {
        if (root.todayShard && hostWidget && hostWidget.settleSchedule) hostWidget.settleSchedule(null)
      }

      Flickable {
        id: infoScroll
        anchors.fill: parent
        contentWidth: infoColumn.width
        contentHeight: infoColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: infoColumn
          width: Math.max(infoScroll.width, titleCard.implicitWidth)
          spacing: Style.space(12)

          // ---- Title card: logo + name + rotating subtitle -------------
          Rectangle {
            id: titleCard
            width: parent.width
            height: titleRow.implicitHeight + Style.space(20)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius * 1.5 : 0
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
            border.width: Style.spacing.hairline
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)

            Row {
              id: titleRow
              x: Style.space(14)
              y: Style.space(10)
              width: parent.width - Style.space(28)
              spacing: Style.space(12)

              Image {
                anchors.verticalCenter: parent.verticalCenter
                source: Qt.resolvedUrl("assets/tgc-logo.png")
                width: Math.round(Style.font.title * 1.4)
                height: Math.round(Style.font.title * 1.4)
                fillMode: Image.PreserveAspectFit
                smooth: true
                sourceSize.width: Math.round(Style.font.title * 2.8)
                sourceSize.height: Math.round(Style.font.title * 2.8)
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: "✦ OmaShard"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                // Subtitle sits under the title, italic and quiet.
                Text {
                  text: root.subtitle
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.72)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.italic: true
                }
              }
            }
          }

          // ---- Today's shard --------------------------------------------
          Text {
            text: root.fetchError && !root.todayShard ? "OFFLINE — " + root.fetchError.toUpperCase() : "TODAY'S SHARD"
            color: root.fetchError && !root.todayShard ? root.redColor : Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
            font.bold: true
          }

          Item {
            id: todayCard
            width: parent.width
            height: root.todayShard ? todayRow.height : noShardRow.height

            Row {
              id: todayRow
              visible: root.todayShard !== null
              width: parent.width
              spacing: Style.space(14)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.todayShard ? root.colorDot(root.todayShard.shardColor) : ""
                font.pixelSize: Style.font.display
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: root.todayShard ? root.todayShard.realm : ""
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  text: root.todayShard
                    ? (root.todayShard.map + (root.todayShard.rewardAc ? "  ·  " + String(root.todayShard.rewardAc) + " AC" : ""))
                    : ""
                  color: Qt.darker(root.contentForeground, 1.35)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  text: root.todayShard
                    ? (root.todayShard.shardColor + " shard" + (root.todayShard.variant > 1 ? " · " + root.todayShard.variant + " variants" : ""))
                    : ""
                  color: root.todayShard && root.todayShard.shardColor === "Red"
                    ? root.redColor
                    : (root.todayShard && root.todayShard.shardColor === "Black"
                      ? Qt.darker(root.contentForeground, 1.6)
                      : root.contentForeground)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
              }
            }

            Row {
              id: noShardRow
              visible: root.todayShard === null
              width: parent.width
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "🌤"
                font.pixelSize: Style.font.body
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: root.loading ? "Checking the skies…" : "No shard lands today"
                  color: Qt.darker(root.contentForeground, 1.2)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  text: root.fetchError ? root.fetchError : "The realms rest peacefully"
                  visible: !root.loading
                  color: Qt.darker(root.contentForeground, 1.6)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // ---- Eruption windows -----------------------------------------
          Text {
            text: "ERUPTION TIMES · " + root.tzLabel.toUpperCase()
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
            font.bold: true
          }

          Column {
            id: timesColumn
            width: parent.width
            spacing: Style.space(6)
            visible: root.todayShard !== null && root.todayShard.occurrences.length > 0

            Repeater {
              model: root.todayShard ? root.todayShard.occurrences : []

              Rectangle {
                required property var modelData
                width: parent ? parent.width : 0
                height: Style.space(26)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Text {
                    text: root.occurrenceSummary(modelData)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }

            Text {
              text: "start → land → end"
              color: Qt.darker(root.contentForeground, 1.8)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              anchors.horizontalCenter: parent.horizontalCenter
            }
          }

          // ---- Upcoming --------------------------------------------------
          Text {
            visible: upcomingShards().length > 0
            text: "UPCOMING"
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
            font.bold: true
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: upcomingShards().length > 0

            Repeater {
              model: upcomingShards()

              Rectangle {
                required property var modelData
                width: parent ? parent.width : 0
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Text {
                    text: root.dayLabel(modelData.date, modelData === root.nextShard)
                    width: Style.space(52)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  Text {
                    text: root.colorDot(modelData.shardColor)
                    color: root.contentForeground
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: modelData.map + " — " + modelData.realm
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: modelData.rewardAc ? String(modelData.rewardAc) + " AC" : ""
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---- Footer -----------------------------------------------------
          Item {
            width: parent.width
            height: Style.space(2)
            visible: root.fetchError !== ""
          }

          Text {
            visible: root.fetchError !== ""
            text: "Live data unavailable — showing computed schedule"
            color: Qt.darker(root.contentForeground, 1.8)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}