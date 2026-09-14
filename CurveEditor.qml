import QtQuick
import qs.Commons
import qs.Ui

// A cubic bezier with both endpoints pinned at (0,0) and (1,1), which is what
// Hyprland's `bezier` is. Only the two control handles move.
//
// The unit square is drawn square and centred, with room above and below it:
// easeOutQuint sits at y=1 and overshooting curves go past it, so clamping the
// axis to 0..1 would quietly flatten curves the user can legitimately write,
// and stretching x across the panel would flatten every curve visually.
//
// The play strip below the graph runs the same four numbers through QML's own
// Easing.Bezier for the leaf's real duration, so "how does this feel" is
// answered without opening a window.
Item {
  id: root

  property var points: [0.25, 0.1, 0.25, 1]
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  // Duration of the leaf being edited, in deciseconds.
  property real previewSpeed: 3

  signal changed(var points)
  signal committed(var points)

  readonly property real yMin: -0.35
  readonly property real yMax: 1.35
  readonly property int pad: Style.space(14)

  property int activeHandle: -1

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function plotX(x) { return pad + x * (plot.width - pad * 2) }
  function plotY(y) {
    var t = (y - yMin) / (yMax - yMin)
    return plot.height - pad - t * (plot.height - pad * 2)
  }
  function valueX(px) { return clamp((px - pad) / Math.max(1, plot.width - pad * 2), 0, 1) }
  function valueY(py) {
    var t = (plot.height - pad - py) / Math.max(1, plot.height - pad * 2)
    return clamp(yMin + t * (yMax - yMin), yMin, yMax)
  }

  function withHandle(index, x, y) {
    var next = [Number(points[0]), Number(points[1]), Number(points[2]), Number(points[3])]
    next[index * 2] = Math.round(x * 1000) / 1000
    next[index * 2 + 1] = Math.round(y * 1000) / 1000
    return next
  }

  function play() {
    marker.stop()
    marker.progress = 0
    marker.duration = Math.max(40, Math.round(root.previewSpeed * 100))
    marker.start()
  }

  implicitHeight: graph.implicitHeight + strip.implicitHeight + readout.implicitHeight + Style.spacing.lg * 2

  Column {
    anchors.fill: parent
    spacing: Style.spacing.lg

    Item {
      id: graph
      width: parent.width
      implicitHeight: Style.space(360)
      height: implicitHeight

      // Square unit box, centred. Width follows height so that one unit of x
      // and one unit of y are the same number of pixels.
      Item {
        id: plot
        height: parent.height
        width: Math.min(parent.width,
                        Math.round((height - root.pad * 2) / (root.yMax - root.yMin)) + root.pad * 2)
        anchors.horizontalCenter: parent.horizontalCenter

        Canvas {
          id: canvas
          anchors.fill: parent
          antialiasing: true

          // Repainting off a plain binding would miss an in-place array edit,
          // so the parent's points are read through a change signal instead.
          Connections {
            target: root
            function onPointsChanged() { canvas.requestPaint() }
          }
          Connections {
            target: Color
            function onAccentChanged() { canvas.requestPaint() }
            function onForegroundChanged() { canvas.requestPaint() }
          }

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            var fg = root.foreground
            var accent = root.accent

            // The region a non-overshooting curve stays inside.
            ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.14)
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.rect(root.plotX(0), root.plotY(1), root.plotX(1) - root.plotX(0), root.plotY(0) - root.plotY(1))
            ctx.stroke()

            // Quarter gridlines.
            ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.07)
            for (var g = 1; g < 4; g++) {
              var gx = root.plotX(g / 4)
              ctx.beginPath(); ctx.moveTo(gx, root.plotY(1)); ctx.lineTo(gx, root.plotY(0)); ctx.stroke()
              var gy = root.plotY(g / 4)
              ctx.beginPath(); ctx.moveTo(root.plotX(0), gy); ctx.lineTo(root.plotX(1), gy); ctx.stroke()
            }

            var p = root.points
            var x0 = root.plotX(0), y0 = root.plotY(0)
            var x3 = root.plotX(1), y3 = root.plotY(1)
            var x1 = root.plotX(p[0]), y1 = root.plotY(p[1])
            var x2 = root.plotX(p[2]), y2 = root.plotY(p[3])

            // Handle arms.
            ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.35)
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(x3, y3); ctx.lineTo(x2, y2); ctx.stroke()

            // The curve.
            ctx.strokeStyle = accent
            ctx.lineWidth = Math.max(2, Style.space(2))
            ctx.beginPath()
            ctx.moveTo(x0, y0)
            ctx.bezierCurveTo(x1, y1, x2, y2, x3, y3)
            ctx.stroke()

            // Endpoints, then handles on top.
            ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.5)
            for (var e = 0; e < 2; e++) {
              ctx.beginPath()
              ctx.arc(e === 0 ? x0 : x3, e === 0 ? y0 : y3, Math.max(2.5, Style.space(3)), 0, Math.PI * 2)
              ctx.fill()
            }

            var radius = Math.max(5, Style.space(6))
            for (var h = 0; h < 2; h++) {
              var hx = h === 0 ? x1 : x2
              var hy = h === 0 ? y1 : y2
              ctx.beginPath()
              ctx.arc(hx, hy, radius + (root.activeHandle === h ? Style.space(2) : 0), 0, Math.PI * 2)
              ctx.fillStyle = root.activeHandle === h ? accent : Qt.rgba(accent.r, accent.g, accent.b, 0.75)
              ctx.fill()
              ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.85)
              ctx.lineWidth = 1
              ctx.stroke()
            }
          }
        }

        // One area over the whole graph rather than two draggable handles: it
        // keeps the handle position a pure function of `points`, so a drag can
        // never fight the value it is setting.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.activeHandle >= 0 || nearestHandle(mouseX, mouseY) >= 0
            ? Qt.ClosedHandCursor : Qt.ArrowCursor

          function nearestHandle(mx, my) {
            var grab = Style.space(18)
            var best = -1
            var bestDistance = grab * grab
            for (var i = 0; i < 2; i++) {
              var dx = mx - root.plotX(root.points[i * 2])
              var dy = my - root.plotY(root.points[i * 2 + 1])
              var d = dx * dx + dy * dy
              if (d <= bestDistance) { bestDistance = d; best = i }
            }
            return best
          }

          onPressed: function(mouse) {
            root.activeHandle = nearestHandle(mouse.x, mouse.y)
            if (root.activeHandle < 0) return
            root.changed(root.withHandle(root.activeHandle, root.valueX(mouse.x), root.valueY(mouse.y)))
          }
          onPositionChanged: function(mouse) {
            if (root.activeHandle < 0) return
            root.changed(root.withHandle(root.activeHandle, root.valueX(mouse.x), root.valueY(mouse.y)))
          }
          onReleased: function(mouse) {
            if (root.activeHandle < 0) return
            root.committed(root.withHandle(root.activeHandle, root.valueX(mouse.x), root.valueY(mouse.y)))
            root.activeHandle = -1
          }
          onCanceled: root.activeHandle = -1
        }
      }
    }

    // ------------------------------------------------------------ play strip

    Item {
      id: strip
      width: parent.width
      implicitHeight: Style.space(26)
      height: implicitHeight

      Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: playButton.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(4)
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

        Rectangle {
          id: dot
          width: Style.space(14)
          height: width
          radius: width / 2
          color: root.accent
          anchors.verticalCenter: parent.verticalCenter
          x: marker.progress * (track.width - width)
        }
      }

      PanelActionButton {
        id: playButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰐊"
        tooltipText: "Play at " + Math.round(root.previewSpeed * 100) + " ms  ·  P"
        foreground: root.foreground
        onClicked: root.play()
      }

      // Easing.Bezier takes the two control points followed by the endpoint,
      // which is exactly Hyprland's four numbers plus a pinned (1,1).
      NumberAnimation {
        id: marker
        property real progress: 0
        target: marker
        property: "progress"
        from: 0
        to: 1
        duration: 300
        easing.type: Easing.Bezier
        easing.bezierCurve: [
          root.clamp(root.points[0], 0, 1), root.points[1],
          root.clamp(root.points[2], 0, 1), root.points[3],
          1, 1
        ]
      }
    }

    // -------------------------------------------------------------- readout

    Text {
      id: readout
      width: parent.width
      text: "P1  " + Number(root.points[0]).toFixed(2) + ", " + Number(root.points[1]).toFixed(2)
        + "      P2  " + Number(root.points[2]).toFixed(2) + ", " + Number(root.points[3]).toFixed(2)
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
