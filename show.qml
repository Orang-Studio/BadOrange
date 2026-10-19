// The Bad Orange :: the show.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia
import org.kde.kirigami as Kirigami

Window {
    id: bo
    visible: false
    readonly property var args: {
        var a = Qt.application.arguments, i = a.indexOf("--")
        return a.slice(i + 1)
    }
    readonly property url track: "file://" + encodeURI(args[0])
    readonly property var cues: JSON.parse(args[1])
    readonly property rect area: {
        var s = Qt.application.screens.filter(function (s) { return s.name === args[10] })[0]
        return s ? Qt.rect(s.virtualX, s.virtualY, s.width, s.height) : Qt.rect(+args[2], +args[3], +args[4], +args[5])
    }

    readonly property bool intro: args[6] === "1"
    readonly property real lead: +args[7]
    readonly property real from: +args[9]   
    readonly property int panel: 52
    property real cyan: 0
    property int next: 0
    property real base: 0
    property bool running: false

    MediaPlayer {
        id: player
        source: bo.track
        audioOutput: AudioOutput { volume: +bo.args[8] }
        onPositionChanged: bo.seek()
    }

    Component.onCompleted: {
        hold(watermark.createObject(null))
        intro ? openIntro() : start()
    }

    Shortcut { sequence: "Esc"; context: Qt.ApplicationShortcut; onActivated: Qt.quit() }

    function start() {
        while (next < cues.length && cues[next][0] < from) next++
        base = Date.now() - from * 1000
        player.play()
        seek()
        running = true
    }

    property bool seeked: from <= 0
    function seek() {
        if (seeked || player.position <= 0) return
        seeked = true
        player.position = from * 1000
    }

    function songTime() { return (Date.now() - base) / 1000 }

    Timer {
        interval: 4; repeat: true; running: bo.running
        onTriggered: {
            
            if (player.playbackState === MediaPlayer.PlayingState
                    && Math.abs(player.position - (Date.now() - bo.base)) > 80)
                bo.base = Date.now() - player.position
            var t = bo.songTime() + bo.lead

            while (bo.next < bo.cues.length && bo.cues[bo.next][0] <= t)
                bo.fire(bo.cues[bo.next++])
        }
    }


    function fire(cue) {
        var kind = cue[1], dur = cue[2]
        
        switch (kind) {
        case "error":    return popup(kind, pick(errors, "dialog-error", ["OK"]))
        case "warning":  return popup(kind, pick(warnings, "dialog-warning", ["OK"]))
        case "info":     return popup(kind, pick(infos, "dialog-information", ["OK"]))
        case "question": return popup(kind, pick(questions, "dialog-question", ["Delete", "Cancel"]))
        case "files":    return openFiles()
        case "jump":     return jump()
        case "editor":   return editor(dur)
        case "toast":    toast(); return shake.begin()
        case "glitch":   return hold(glitch.createObject(null, {duration: Math.min(dur, 4)}))   // a burst, not a filter
        case "cyan":     return cyanSwell.restart(dur)
        case "clear":    cyanSwell.stop(); cyan = 0; return wipe.begin(false)
        case "fall":     cyanSwell.stop(); cyan = 0; return wipe.begin(true)
        case "flash":    return hold(flashWin.createObject(null))
        case "tear":     return hold(tearWin.createObject(null))
        case "dvd":      return dvd.begin(dur)
        case "zalgo":    zalgo = true; return
        case "spiral":   spiralUntil = cue[0] + dur; spiralN = 0; return
        case "wall":     return wall.begin(dur)
        case "panic":    hideAll(); return hold(panicScreen.createObject(null))

        default:         // icons-scatter, icons-restore, ...: bad_orange.py moves the real desktop icons
            if (kind.indexOf("icons-") === 0) console.log("ICONS " + kind.slice(6) + " " + dur)

        }
    }

    function rand(n) { return Math.floor(Math.random() * n) }
    property var held: []
    function hold(w) {
        held.push(w)
        w.Component.destruction.connect(function () { held.splice(held.indexOf(w), 1) })
        return w
    }

    function pick(list, icon, buttons) {
        var m = list[rand(list.length)]
        return {title: m[0], text: m[1], icon: icon, buttons: buttons}
    }

    property int boxCap: 36
    property int made: 0
    property var boxes: []
    property var spare: []
    property var wiping: []
    property var chains: ({})

    function takeBox() {
        if (spare.length) return spare.pop()
        if (made < boxCap) {
            made++
            var w = msgBox.createObject(null)
            w.answered.connect(function () { putAway(w) })
            return w
        }
        for (var i = 0; i < wiping.length; i++)     // box
            if (wiping[i].answered) return wiping.splice(i, 1)[0]
        return boxes.shift()      // oldest popup
    }

    function putAway(w) {
        var i = boxes.indexOf(w)
        if (i >= 0) boxes.splice(i, 1)
        w.visible = false
        spare.push(w)
    }

    property real spiralUntil: 0
    property int spiralN: 0
    function nextSpot(kind, w, h) {

        if (songTime() < spiralUntil) {      // spiral out
            var r = 10 + spiralN * 14, a = spiralN * 0.45
            if (r > area.height / 2 - h / 2) { spiralN = 0; r = 10; a = 0 }
            spiralN++
            return Qt.point(area.x + area.width / 2 - w / 2 + r * 1.6 * Math.cos(a),
                            area.y + (area.height - panel) / 2 - h / 2 + r * Math.sin(a))
        }

        var c = chains[kind]
        if (!c || c.n >= c.len) {
            c = chains[kind] = {x: area.x + Math.random() * (area.width - w - 120),
                                y: area.y + Math.random() * (area.height - panel - h - 120),
                                n: 0, len: 3 + rand(4)}
        }

        var p = Qt.point(c.x + c.n * 24, c.y + c.n * 24)
        c.n++
        return p
    }

    property bool zalgo: false

    function rot(s) {
        return s.replace(/\S/g, function (ch) {
            if (Math.random() > 0.3) return ch
            for (var n = 1 + rand(3); n > 0; n--) ch += String.fromCharCode(0x300 + rand(0x70))
            return ch
        })
    }

    function popup(kind, props, at) {
        var w = takeBox()

        w.title = zalgo ? rot(props.title) : props.title
        w.text = zalgo ? rot(props.text) : props.text
        w.icon = props.icon; w.buttons = props.buttons

        var p = at || nextSpot(kind, 480, 150)
        w.x = p.x; w.y = p.y
        if (w.visible) w.raise()
        else w.visible = true
        boxes.push(w)
        return w
    }

    property var files: []
    function openFiles() {
        var w = files.length < 2 ? filesWin.createObject(null) : files.shift()
        w.place = places[rand(places.length)]

        w.x = area.x + Math.random() * (area.width - w.width)
        w.y = area.y + Math.random() * (area.height - panel - w.height)

        if (w.visible) w.raise()
        else w.visible = true
        files.push(w)
    }

    property int edits: 0

    function editor(dur) {
        var e = editorTexts[edits++ % editorTexts.length]
        var w = hold(editorWin.createObject(null, {fileName: e[0], script: e[1], duration: dur}))
        w.x = area.x + Math.random() * (area.width - w.width)
        w.y = area.y + Math.random() * (area.height - panel - w.height)
        w.visible = true
    }

    property var monitor: null
    function jump() {
        if (!monitor) monitor = monitorWin.createObject(null)
        monitor.x = area.x + Math.random() * (area.width - monitor.width)
        monitor.y = area.y + Math.random() * (area.height - panel - monitor.height)
        if (monitor.visible) monitor.raise()
        else monitor.visible = true
    }

    function hideAll() {
        var all = boxes.concat(wiping, files, monitor ? [monitor] : [], dvd.w ? [dvd.w] : [], held)
        for (var i = 0; i < all.length; i++) all[i].visible = false
        spare = spare.concat(boxes, wiping)
        boxes = []; wiping = []
        wipe.stop()
    }

    Timer {
        id: wipe
        repeat: true
        property bool falling
        property var drops: []      // falling
        function begin(fall) {
            var all = bo.wiping.concat(bo.boxes, bo.files, bo.monitor ? [bo.monitor] : [])
            all.sort(function (a, b) { return a.y - b.y })
            bo.wiping = all
            bo.boxes = []
            falling = fall
            interval = fall ? 16 : 8
            drops = all.map(function (w) {
                return {w: w, x: w.x, y: w.y, vx: Math.random() * 8 - 4, vy: -3 - Math.random() * 6, wait: bo.rand(12)}
            })
            start()
        }
        function gone(w) {
            w.visible = false
            bo.wiping.splice(bo.wiping.indexOf(w), 1)
            if (bo.files.indexOf(w) < 0 && w !== bo.monitor) bo.spare.push(w)
        }
        onTriggered: {
            if (!falling) {
                var w = bo.wiping[0]
                return w ? gone(w) : stop()
            }
            drops = drops.filter(function (d) { return bo.wiping.indexOf(d.w) >= 0 })
            if (!drops.length) return stop()
            for (var i = 0; i < drops.length; i++) {
                var d = drops[i]
                if (d.wait-- > 0) continue
                d.vy += 1.8
                d.x += d.vx; d.y += d.vy        // KWin won't let it leave the screen: it's gone at the panel
                if (d.y > bo.area.y + bo.area.height - bo.panel) gone(d.w)
                else { d.w.x = d.x; d.w.y = d.y }
            }
        }
    }

    Timer {

        id: dvd
        interval: 16; repeat: true
        property var w: null
        property real vx: 7
        property real vy: 5
        property real until
        readonly property var icons: ["dialog-error", "dialog-warning", "dialog-information", "dialog-question"]
        function begin(dur) {
            if (!w) w = msgBox.createObject(null, {title: "bad_orange.exe", buttons: ["OK"], icon: icons[0], text: "Bad Orange is now your screensaver."})
            w.x = bo.area.x + bo.area.width / 3; w.y = bo.area.y + bo.area.height / 3
            w.visible = true
            until = Date.now() + dur * 1000
            start()
        }

        onTriggered: {
            if (Date.now() > until) { stop(); w.destroy(); w = null; return }
            var r = bo.area, bounced = false
            if (w.x + vx < r.x || w.x + w.width + vx > r.x + r.width) { vx = -vx; bounced = true }
            if (w.y + vy < r.y || w.y + w.height + vy > r.y + r.height - bo.panel) { vy = -vy; bounced = true }
            w.x += vx; w.y += vy
            if (bounced) { w.icon = icons[(icons.indexOf(w.icon) + 1) % icons.length]; w.raise() }
        }
    }

    Timer {

        id: shake
        interval: 16; repeat: true
        property var targets: []
        property int ticks: 0
        function begin() {
            if (running) return
            targets = bo.boxes.slice(-6).map(function (w) { return {w: w, x: w.x, y: w.y} })
            ticks = 0
            start()
        }

        onTriggered: {
            var a = 14 * (1 - ticks / 22)
            for (var i = 0; i < targets.length; i++) {
                var t = targets[i]
                if (bo.boxes.indexOf(t.w) < 0) continue   // reused meanwhile, leave it be
                t.w.x = t.x + (ticks < 22 ? (Math.random() * 2 - 1) * a : 0)
                t.w.y = t.y + (ticks < 22 ? (Math.random() * 2 - 1) * a : 0)
            }
            if (++ticks > 22) stop()
        }
    }

    function toast() {
        console.log("NOTIFY " + JSON.stringify(toastTexts[rand(toastTexts.length)]))
    }

    Timer {
        id: cyanSwell
        property int step: 0
        repeat: true
        function restart(dur) { step = 0; interval = dur * 1000 / 8; start() }
        onTriggered: {
            bo.cyan = Math.pow(++step / 8, 2)
            if (step >= 8) stop()
        }
    }

    Timer {
        id: wall
        property var cells: []
        repeat: true
        function begin(dur) {

            var cw = 380, ch = 120, list = []

            for (var y = 0; y + ch <= bo.area.height - bo.panel; y += ch * 0.8)
                for (var x = 0; x + cw <= bo.area.width; x += cw * 0.85)
                    list.push(Qt.point(bo.area.x + x, bo.area.y + y))

            for (var i = list.length - 1; i > 0; i--) {           // shuffle
                var j = bo.rand(i + 1), t = list[i]; list[i] = list[j]; list[j] = t
            }

            bo.boxCap = Math.min(list.length + 8, 72)               // cover it
            cells = list
            interval = dur * 1000 / list.length
            start()
        }

        onTriggered: {
            var c = cells.pop()
            if (!c) return stop()
            bo.popup("wall", bo.pick(bo.errors, "dialog-error", ["OK"]),
                     Qt.point(c.x + bo.rand(30) - 15, c.y + bo.rand(30) - 15))
        }
    }


    Component {
        id: msgBox
        Window {
            id: box
            property string icon
            property string text
            property var buttons
            signal answered(string button)
            flags: Qt.Dialog | Qt.WindowStaysOnTopHint
            width: Math.max(row.implicitWidth, answers.implicitWidth) + 40
            height: col.implicitHeight + 32
            color: Qt.tint(palette.window, Qt.rgba(0, 1, 1, bo.cyan * 0.85))

            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                RowLayout {
                    id: row
                    spacing: 14
                    Kirigami.Icon {
                        source: box.icon
                        Layout.preferredWidth: 48; Layout.preferredHeight: 48
                        Layout.alignment: Qt.AlignTop
                    }
                    Label {
                        id: label
                        text: box.text
                        wrapMode: Text.Wrap
                        Layout.preferredWidth: Math.min(implicitWidth, 400)
                    }
                }
                RowLayout {
                    id: answers
                    Layout.alignment: Qt.AlignRight
                    Repeater {
                        model: box.buttons
                        Button {
                            text: modelData
                            icon.name: ({OK: "dialog-ok", Delete: "edit-delete", Cancel: "dialog-cancel", Open: "document-open"})[modelData]
                            onClicked: box.answered(modelData)
    }   }   }   }   }   }

    Component {
        id: filesWin
        Window {

            id: fw
            property var place: bo.places[0]
            title: place.name + " - Dolphin"
            flags: Qt.Window | Qt.WindowStaysOnTopHint
            width: 820; height: 500
            color: Qt.tint(palette.window, Qt.rgba(0, 1, 1, bo.cyan * 0.85))

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                ToolBar {
                    Layout.fillWidth: true
                    RowLayout {
                        anchors.fill: parent
                        ToolButton { icon.name: "go-previous" }
                        ToolButton { icon.name: "go-next" }
                        Label { text: fw.place.path; Layout.fillWidth: true; leftPadding: 8 }
                        ToolButton { icon.name: "view-list-icons" }
                        ToolButton { icon.name: "edit-find" }
                    }
                }

                RowLayout {
                    spacing: 0
                    Layout.fillWidth: true; Layout.fillHeight: true
                    ListView {
                        Layout.preferredWidth: 170; Layout.fillHeight: true
                        interactive: false
                        model: bo.sidebar
                        delegate: ItemDelegate {
                            width: 170
                            text: modelData[1]
                            icon.name: modelData[0]
                            highlighted: modelData[1] === fw.place.name
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        color: Qt.tint(palette.base, Qt.rgba(0, 1, 1, bo.cyan * 0.85))
                        GridView {
                            anchors.fill: parent; anchors.margins: 10
                            interactive: false
                            cellWidth: 104; cellHeight: 96
                            model: fw.place.files
                            delegate: Column {
                                width: 100
                                spacing: 4
                                Kirigami.Icon {
                                    source: modelData[0]
                                    width: 56; height: 56
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Label {
                                    text: modelData[1]
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                    }
                }

                Label {
                    text: fw.place.files.length + " items"
                    padding: 6

                }
            }
        }
    }

    Component {
        id: editorWin
        Window {
            id: ew
            property string fileName
            property string script
            property real duration          // seconds until it closes again
            property int typed: 0
            readonly property string shown: script.slice(0, typed)
            readonly property int lines: shown.split("\n").length
            title: fileName + (typed < script.length ? " [modified]" : "") + " - KWrite"
            flags: Qt.Window | Qt.WindowStaysOnTopHint
            width: 600; height: 340
            color: palette.window

            Timer {
                interval: Math.max(15, ew.duration * 700 / ew.script.length); repeat: true; running: true
                onTriggered: if (++ew.typed >= ew.script.length) stop()
            }

            Timer { interval: ew.duration * 1000; running: true; onTriggered: ew.destroy() }
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                ToolBar {
                    Layout.fillWidth: true
                    RowLayout {

                        ToolButton { icon.name: "document-new" }
                        ToolButton { icon.name: "document-open" }
                        ToolButton { icon.name: "document-save" }
                        ToolButton { icon.name: "edit-undo" }
                        ToolButton { icon.name: "edit-redo" }

                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    color: palette.base
                    clip: true

                    Row {
                        x: 6; y: 6
                        spacing: 10
                        Text {
                            text: Array.from({length: ew.lines}, function (_, i) { return i + 1 }).join("\n")
                            font.family: "monospace"
                            color: palette.placeholderText
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            text: ew.shown + (Math.floor(ew.typed / 6) % 2 ? "▏" : "")
                            font.family: "monospace"
                            color: palette.text
                        }
                    }
                }

                Label {
                    text: "Line " + ew.lines + ", Col " + (ew.shown.length - ew.shown.lastIndexOf("\n")) + "    INSERT    UTF-8"
                    padding: 5
                    opacity: 0.8
                }
            }
        }
    }

    Component {

        id: monitorWin
        Window {
            title: "System Monitor"
            flags: Qt.Window | Qt.WindowStaysOnTopHint
            width: 640; height: 400
            color: palette.window

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                ToolBar {
                    Layout.fillWidth: true
                    RowLayout {
                        anchors.fill: parent
                        Label { text: "Processes"; font.bold: true; leftPadding: 8; Layout.fillWidth: true }
                        TextField { placeholderText: "Search"; Layout.preferredWidth: 180 }
                        Button { text: "End Process"; icon.name: "process-stop" }
                    }
                }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    interactive: false
                    model: bo.processes
                    header: RowLayout {
                        width: ListView.view.width
                        Label { text: "Name"; font.bold: true; Layout.fillWidth: true; leftPadding: 10 }
                        Label { text: "CPU"; font.bold: true; Layout.preferredWidth: 70 }
                        Label { text: "Memory"; font.bold: true; Layout.preferredWidth: 90 }
                    }
                    delegate: ItemDelegate {
                        width: ListView.view.width
                        highlighted: index === 0
                        contentItem: RowLayout {
                            Kirigami.Icon { source: modelData[0]; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                            Label { text: modelData[1]; Layout.fillWidth: true }
                            Label { text: modelData[2]; Layout.preferredWidth: 70 }
                            Label { text: modelData[3]; Layout.preferredWidth: 90 }
    }   }   }   }   }   }

    Component {
        id: glitch
        Window {
            id: gw
            property real duration
            readonly property real born: Date.now()
            flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
            color: "transparent"
            x: bo.area.x; y: bo.area.y
            width: bo.area.width; height: bo.area.height
            visible: true

            Repeater {
                id: blocks
                model: 220
                Rectangle {
                    // each block shows up at its own moment in the first half of the burst
                    readonly property real at: Math.random() * gw.duration * 500
                    readonly property real s: 14 + Math.random() * 18
                    width: s; height: s
                    x: Math.random() * (gw.width - s); y: Math.random() * (gw.height - s)
                    visible: false
                }
            }

            Timer {
                interval: 40; repeat: true; running: true
                onTriggered: {
                    var age = Date.now() - gw.born
                    if (age > gw.duration * 1000) return gw.destroy()
                    for (var i = 0; i < blocks.count; i++) {
                        var b = blocks.itemAt(i), t = age - b.at
                        if (t < 0) continue
                        if (t < 480) {                        // red, blinking
                            b.color = "#d01818"
                            b.visible = Math.floor(t / 80) % 2 === 0
                        } else {                              // ...and it's an orange now
                            b.color = "#ff8a00"
                            b.visible = true
    }   }   }   }   }   }

    Component {
        id: watermark

        Window {
            flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
            color: "transparent"
            width: 360; height: 64
            x: bo.area.x + bo.area.width - width - 24
            y: bo.area.y + bo.area.height - bo.panel - height - 16
            visible: true

            Column {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                Text { text: "Activate Linux"; color: "#99ffffff"; font.pointSize: 17 }
                Text { text: "Go to Settings to activate Linux."; color: "#99ffffff"; font.pointSize: 11 }

            }
        }
    }

    Component {
        id: flashWin

        Window {
            id: fl
            flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
            color: "white"
            x: bo.area.x; y: bo.area.y
            width: bo.area.width; height: bo.area.height
            visible: true
            NumberAnimation on opacity { from: 0.6; to: 0; duration: 300; onFinished: fl.destroy() }
        }
    }

    Component {
        id: tearWin

        Window {
            id: tear
            property int ticks: 0
            flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
            color: "transparent"
            x: bo.area.x; y: bo.area.y
            width: bo.area.width; height: bo.area.height
            visible: true

            Repeater {
                id: bands
                model: 7
                Rectangle { width: tear.width; opacity: 0.55 }
            }

            Timer {
                interval: 45; repeat: true; running: true; triggeredOnStart: true
                onTriggered: {
                    if (++tear.ticks > 8) return tear.destroy()
                    for (var i = 0; i < bands.count; i++) {
                        var b = bands.itemAt(i)
                        b.y = Math.random() * tear.height; b.height = 3 + Math.random() * 40
                        b.x = Math.random() * 60 - 30
                        b.color = ["#00ffff", "#ff00ff", "#ff8a00", "#ffffff"][bo.rand(4)]
                    }
                }
            }
        }
    }

    Component {
        id: panicScreen

        Window {
            flags: Qt.ToolTip | Qt.FramelessWindowHint
            color: "black"
            x: bo.area.x; y: bo.area.y
            width: bo.area.width; height: bo.area.height
            visible: true
            Timer { interval: 7000; running: true; onTriggered: Qt.quit() }
            MouseArea { anchors.fill: parent; cursorShape: Qt.BlankCursor; onClicked: Qt.quit() }

            Row {
                x: 10; y: 10
                spacing: 6
                Repeater {
                    model: 3
                    Image { source: Qt.resolvedUrl("crash.webp"); sourceSize: Qt.size(68, 80); smooth: true }
                }
            }

            Column {
                id: msg
                anchors.centerIn: parent
                spacing: 14
                Label { text: "KERNEL PANIC!"; color: "white"; font.pointSize: 28; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                Label { text: "Please reboot your computer."; color: "white"; font.pointSize: 14; anchors.horizontalCenter: parent.horizontalCenter }
                Item { width: 1; height: 30 }
                Label { text: "Kernel panic - not syncing: Attempted to kill init! exitcode=0x0000b4d0"; color: "#bbbbbb"; font.family: "monospace" }
                Label { text: "CPU: 0 PID: 1 Comm: bad_orange Tainted: G      D     7.2.10-1-cachyos"; color: "#bbbbbb"; font.family: "monospace" }
            }
            Timer { interval: 4500; running: true; onTriggered: msg.visible = false }   // then just black
        }
    }

    function openIntro() {

        var w = hold(msgBox.createObject(null, {
            title: "Open File - Dolphin", icon: "dialog-question", buttons: ["Open", "Cancel"],
            text: "Do you want to open virus \"bad_orange.trash\"?\n\nThis file can cause you sickness and could in some way make your system blow up.."}))

        w.x = area.x + (area.width - w.width) / 2; w.y = area.y + (area.height - w.height) / 2

        w.answered.connect(function (b) {
            if (b !== "Open") return Qt.quit()
            w.destroy()
            start()
        })
        w.visible = true
    }


    readonly property var errors: [
        ["Error - Dolphin", "Could not enter folder /home. Access denied."],
        ["Error - plasmashell", "The operation completed successfully."],
        ["Error - KWin", "The compositor has crashed and is now composing itself."],
        ["Error - Konsole", "Kernel panic - not syncing: Attempted to kill init!"],
        ["Disk Error - KDE Partition Manager", "Could not write to /dev/nvme0n1p2. Data loss is likely."],
        ["Error", "Error: no error."],
        ["Error - kded6", "Out of memory: unable to allocate 4 bytes."],
        ["Network Error - KIO", "Connection reset by peer. Peer reset by connection."],
        ["Error - Discover", "Rolling back the update..."],
        ["Error - Dolphin", "The file cannot be deleted because it does not exist."],
        ["Error - kwin_wayland", "Your graphics driver has stopped responding."],
        ["Bad Orange", "Bad Orange has encountered a problem and needs to continue."],
        ["Error - PipeWire", "The audio device is busy."],
        ["Error - systemd", "Failed to start bad_orange.service: Unit is already running."],
        ["Error - Ark", "The archive \"home.tar.zst\" is corrupted beyond repair."],
        ["Error - KWallet", "The wallet \"kdewallet\" was opened by somebody else."],
        ["Error - Baloo", "File indexer found 1 apple. It is bad."],
        ["Error - Konsole", "segmentation fault (core dumped)    ./bad_orange"],
        ["Error - plasmashell", "Plasma has stopped. Plasma has started. Plasma has stopped."],
        ["Error - pacman", "error: failed to commit transaction (conflicting files)\nbad_orange: /usr/bin/everything exists in filesystem"],
    ]
    readonly property var warnings: [
        ["Warning - KDE Connect", "A device named \"BAD-APPLE\" is reading your clipboard."],
        ["Warning - System Settings", "Your settings have been changed by somebody who is not you."],
        ["Warning - Plasma", "Battery critically low (0%). Shutting down in 3... 2..."],
        ["Warning - KWin", "Desktop effects were turned off because they were too effective."],
        ["Warning - Dolphin", "The folder \"Home\" is too large to be your home."],
        ["Warning - polkit", "An unknown application is requesting root access."],
        ["Warning - Discover", "547 updates are available. None of them will help."],
        ["Warning - KDE Partition Manager", "The partition table looks like an apple."],
        ["Warning - Firewall", "Incoming connection from 127.0.0.1. It knows where you live."],
        ["Warning - Spectacle", "A screenshot of you was taken."],
        ["Warning", "This program has performed an illegal operation."],
        ["Warning - Konsole", "The process \"bad_orange\" is still running. Close anyway?"],
    ]
    readonly property var infos: [
        ["Information - Bad Orange", "Your files are being converted into oranges."],
        ["Information - KDE Connect", "Your phone is ringing. It is also ringing you."],
        ["Information - Plasma", "A new desktop has been created. You are on it."],
        ["Information - Discover", "Installing bad_orange (1 of 1)..."],
        ["Information - Dolphin", "Moved 1 file to Trash: \"Home\"."],
        ["Information - KRunner", "Searching for a way out..."],
        ["Information - Bad Orange", "Dancing. Please wait."],
        ["Information - System Monitor", "CPU 1 is at 100%."],
        ["Information - KDE", "Did you know? You can press Esc to stop this."],
        ["Information - Bad Orange", "Nothing is wrong. Everything is fine."],
        ["Information - Plasma", "Your wallpaper has been replaced with a slightly worse wallpaper."],
        ["Information - Kate", "Document \"diary.txt\" was modified by another program."],
    ]
    readonly property var questions: [
        ["Delete Permanently - Dolphin", "Do you really want to delete \"libc.so.6\"?\nThis action cannot be undone."],
        ["Delete Permanently - Dolphin", "Do you really want to delete \"vmlinuz-linux-cachyos\"?"],
        ["Delete Permanently - Dolphin", "Do you really want to delete 31,337 items?"],
        ["Delete Permanently - Dolphin", "Do you really want to delete \"/home\"?"],
        ["Delete Permanently - Dolphin", "Do you really want to delete \"kwin_wayland\"?\nThis action cannot be undone."],
        ["Delete Permanently - Dolphin", "Do you really want to delete \"bad_apple.mp4\"? It is still playing."],
        ["Delete Permanently - Dolphin", "Do you really want to delete \"System32\"?\n(this is linux btw)"],
    ]
    readonly property var toastTexts: [
        ["Disk Failure", "S.M.A.R.T. says /dev/nvme0n1 is having a bad day."],
        ["Kernel Event", "The system rebooted without shutting down first."],
        ["Plasma Crashed", "plasmashell closed unexpectedly. It will be back. It is always back."],
        ["Overheating", "CPU temperature: 104 °C."],
        ["Audio Device Lost", "PipeWire lost the speakers."],
        ["Memory Error", "Uncorrectable ECC error at address 0xBADA991E."],
        ["Update Failed", "Kernel 7.2.10 could not be replaced with Bad Apple 1.0."],
    ]
    readonly property var editorTexts: [
        ["bad_orange.sh", "#!/bin/bash\n# bad_orange v1.0 - peel everything\n\necho \"peeling $HOME ...\"\nfor f in ~/Documents/*; do\n    mv \"$f\" \"${f%.*}.orange\"\ndone\necho \"done. everything is an orange now.\""],
        ["notes.txt", "day 1: just downloaded some ram :D.\nday 2: windows move when i'm not looking??\nday 3: i hear music. nobody is playing music.\nday 4: it's bad apple.\nday 5: it's always bad apple."],
        ["fstab", "# /etc/fstab: static file system information\n#\nUUID=BAD-APPLE  /      ext4    defaults  0 1\nUUID=0RANGE     /home  orange  peeled    0 2\ntmpfs           /tmp   tmpfs   apples    0 0"],
        ["main.cpp", "#include <iostream>\n\nint main() {\n    while (true) {\n        std::cout << \"Bad Apple!!\\n\";\n        spawn_popup();   // TODO: stop??\n    }\n}"],
        ["README_NOW.txt", "Hello.\n\nYour computer is fine.\nPlease do not look at the windows.\nThe windows are also fine.\n\n        - bad orange"],
        ["config", "[General]\nSanity=false\nPopups=yes\nPopupsPerSecond=lots\nMusic=Bad Apple!!\nAllowEscape=false   # press Esc"],
    ]
    readonly property var processes: [
        ["application-x-executable", "bad_orange", "99.9%", "13.37 GiB"],
        ["preferences-system-windows", "kwin_wayland", "48.0%", "512.0 MiB"],
        ["plasmashell", "plasmashell", "31.2%", "690.4 MiB"],
        ["audio-card", "pipewire", "12.5%", "48.2 MiB"],
        ["system-file-manager", "dolphin", "4.0%", "120.6 MiB"],
        ["utilities-terminal", "konsole", "1.1%", "64.0 MiB"],
        ["applications-system", "systemd", "0.3%", "16.1 MiB"],
        ["application-x-executable", "bad_orange (2)", "99.9%", "13.37 GiB"],
    ]
    readonly property var sidebar: [
        ["user-home", "Home"], ["user-desktop", "Desktop"], ["folder-documents", "Documents"],
        ["folder-download", "Downloads"], ["folder-music", "Music"], ["folder-pictures", "Pictures"],
        ["folder-videos", "Videos"], ["user-trash", "Trash"], ["drive-harddisk", "Root"],
    ]
    readonly property var places: [
        {name: "Trash", path: "trash:/", files: [
            ["folder", "home"], ["folder", "Documents"], ["folder-pictures", "Pictures"], ["text-plain", "passwords.txt"],
            ["application-x-executable", "kwin_wayland"], ["application-x-sharedlib", "libc.so.6"],
            ["text-x-script", "fix_everything.sh"], ["video-x-generic", "bad_apple.mp4"]]},
        {name: "Root", path: "/", files: [
            ["folder", "bin"], ["folder", "boot"], ["folder", "dev"], ["folder", "etc"], ["folder", "home"],
            ["folder", "lib"], ["folder", "orange"], ["folder", "proc"], ["folder", "root"], ["folder", "usr"],
            ["application-x-executable", "bad_orange"]]},
        {name: "Downloads", path: "/home / Downloads", files: [
            ["application-x-executable", "bad_orange.AppImage"], ["application-x-executable", "bad_orange (1).AppImage"],
            ["application-x-executable", "bad_orange (2).AppImage"], ["audio-x-generic", "Bad Apple (KDE).wav"],
            ["application-x-compressed-tar", "free_ram.tar.zst"], ["text-plain", "README_NOW.txt"]]},
        {name: "Documents", path: "/home / Documents", files: [
            ["folder", "homework"], ["application-vnd.oasis.opendocument.text", "homework_final_FINAL.odt"],
            ["text-plain", "diary.txt"], ["image-png", "orange.png"], ["image-png", "orange (2).png"],
            ["text-plain", "your_files_are_oranges_now.txt"]]},
        {name: "Desktop", path: "/home / Desktop", files: [
            ["folder", "BadApple project"], ["folder", "The Bad Orange"], ["application-x-executable", "Normal OS"],
            ["user-trash", "Trash"], ["text-x-script", "bad_orange.py"]]},
    ]
}