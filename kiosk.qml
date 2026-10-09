import QtQuick
import QtQuick.Window
import QtWebEngine

// Fullscreen kiosk window for a Corsair Xeneon Edge (2560x720) or any secondary panel.
//
//   qml6 kiosk.qml -- [--output=DP-4] [--hold=YYYY-MM-DD] [--shot]
//
// Picks the screen named by --output; without it, the first 2560x720 screen.
// Re-pins itself if screens change (hotplug / resume). Esc quits, F5 reloads,
// F12 saves screenshot.png next to the page (--shot does the same 4 s after start).
Window {
    id: win
    title: "Edge Dash"
    color: "#faf4ec"
    visible: false
    flags: Qt.Window | Qt.FramelessWindowHint

    readonly property var args: Qt.application.arguments
    function arg(name) {
        for (var i = 0; i < args.length; i++)
            if (args[i].indexOf(name + "=") === 0) return args[i].substring(name.length + 1)
        return ""
    }
    property string targetName: arg("--output")
    property int targetW: 2560
    property int targetH: 720
    property string page: Qt.resolvedUrl("index.html") + (arg("--hold") ? "?hold=" + arg("--hold") : "")

    function findTarget() {
        var scr = Qt.application.screens, byRes = null
        for (var i = 0; i < scr.length; i++) {
            if (targetName && scr[i].name === targetName) return scr[i]
            if (!byRes && scr[i].width === targetW && scr[i].height === targetH) byRes = scr[i]
        }
        return byRes
    }

    function place() {
        var t = findTarget()
        if (!t) {
            console.warn("edge-dash: target screen not found (" + (targetName || targetW + "x" + targetH) + "), retrying in 5s")
            win.visible = false
            retry.restart()
            return
        }
        win.screen = t
        win.x = t.virtualX; win.y = t.virtualY
        win.width = t.width; win.height = t.height
        win.visible = true
        win.visibility = Window.FullScreen
        console.warn("edge-dash: on", t.name, t.width + "x" + t.height)
    }

    Component.onCompleted: place()
    Timer { id: retry; interval: 5000; onTriggered: place() }
    Connections { target: Qt.application; function onScreensChanged() { place() } }

    WebEngineView {
        id: view
        anchors.fill: parent
        url: win.page
        backgroundColor: win.color
        settings.showScrollBars: false
        settings.localContentCanAccessRemoteUrls: true   // lets index.html pull remote iframes/APIs if you add any
        settings.localContentCanAccessFileUrls: true     // index.html reads schedule.json over XHR
        onContextMenuRequested: function(request) { request.accepted = true }
        onLoadingChanged: function(info) {
            if (info.status === WebEngineView.LoadFailedStatus)
                console.warn("edge-dash: load failed", info.errorString)
        }
    }

    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { sequence: "F5"; onActivated: view.reload() }
    Shortcut { sequence: "F12"; onActivated: win.shoot() }

    function shoot() {
        view.grabToImage(function(result) {
            var p = Qt.resolvedUrl("screenshot.png").toString().replace("file://", "")
            result.saveToFile(p); console.warn("edge-dash: screenshot", p)
        })
    }
    Timer { id: shotTimer; interval: 4000; running: args.indexOf("--shot") >= 0; onTriggered: win.shoot() }
}
