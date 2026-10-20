import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The pxm window: everything about local PHP development in one place.
// Data comes from the pxm CLI (`pxm status --json`, `pxm php info --json`, `pxm logs --json`);
// every action calls the pxm CLI, so the window and the terminal always agree.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool closingFromHost: false

  property string section: "sites"
  property var st: ({ global: "", global_full: "", installed: [], available: [], installing: [], prereleases: [],
                      buildable: [], building: ({}), sites: ({}), services: [], sites_dir: "", trusted: true })
  property var phpInfo: []
  property var logData: ({ site: "", files: [] })
  property string logSite: ""
  property string busy: ""
  property string svcBusy: ""
  property string shareBusy: ""
  property string toast: ""
  property bool creatingSite: false
  property string expandedExt: ""
  property var prefs: ({})
  readonly property var prefKinds: [
    { id: "editor", title: "Editor", hint: "Used by the Editor buttons, Edit php.ini and log files." },
    { id: "terminal", title: "Terminal", hint: "Used by the Terminal buttons and New Laravel site." },
    { id: "files", title: "File manager", hint: "Used by the Folder buttons." },
    { id: "browser", title: "Browser", hint: "Used to open your .test sites, the Mailpit inbox and other links." }
  ]

  readonly property color fg: Color.foreground
  readonly property color bg: Color.background
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color card: Qt.rgba(fg.r, fg.g, fg.b, 0.04)
  readonly property color sidebarBg: Qt.rgba(fg.r, fg.g, fg.b, 0.03)
  readonly property string ff: Style.font.family
  readonly property string home: Quickshell.env("HOME")
  readonly property string pxm: decodeURIComponent(Qt.resolvedUrl("bin/pxm").toString().replace(/^file:\/\//, ""))
  readonly property bool ready: st.ready !== false
  readonly property string snake: "󱔎"

  readonly property var sections: [
    { id: "sites", label: "Sites", icon: "" },
    { id: "php", label: "PHP", icon: "" },
    { id: "node", label: "Node", icon: "\ue718" },
    { id: "services", label: "Services", icon: "" },
    { id: "mail", label: "Mail", icon: "" },
    { id: "logs", label: "Logs", icon: "" },
    { id: "settings", label: "Settings", icon: "\uf013" }
  ]
  readonly property var siteList: {
    var out = []
    var s = st.sites || {}
    for (var k in s) out.push(Object.assign({ name: k }, s[k]))
    return out
  }
  readonly property var siteNames: siteList.map(function(s) { return s.name })
  readonly property var activeMinors: {
    var out = []
    var inst = st.installed || []
    for (var i = 0; i < inst.length; i++) if (inst[i].active) out.push(inst[i].minor)
    return out
  }
  readonly property var globalChoices: (st.system ? ["system"] : []).concat(activeMinors)
  readonly property var sitePhpChoices: [{ value: "Global", label: "PHP: global (" + (st.global === "system" ? "system" : st.global) + ")" }]
    .concat(activeMinors.map(function(m) { return { value: m, label: "PHP " + m } }))
    .concat(st.system ? [{ value: "system", label: "PHP: system" }] : [])
  readonly property var node: st.node || ({ majors: [], lines: [], installed: [], installing: [], global_major: "", global: "", global_spec: "", nvmrc: false })
  readonly property var siteNodeChoices: [{ value: "Global", label: "Node: global (" + (node.global_major || "–") + ")" }]
    .concat((node.majors || []).map(function(m) { return { value: m.major, label: "Node " + m.major } }))
  function nodeInstalling(major) { return (node.installing || []).indexOf(String(major)) !== -1 }
  readonly property var installable: (st.available || []).filter(function(a) { return !a.installed })
  readonly property var buildingList: {
    var out = []
    var b = st.building || {}
    for (var k in b) out.push({ spec: k, status: b[k] })
    return out
  }
  readonly property var mailpit: {
    var s = st.services || []
    for (var i = 0; i < s.length; i++) if (s[i].id === "mailpit") return s[i]
    return null
  }

  // ---------------------------------------------------------------- host API
  function open(payloadJson) {
    closingFromHost = false
    try {
      var p = JSON.parse(String(payloadJson || "{}"))
      if (p && p.section) section = p.section
      if (p && p.site) logSite = p.site
    } catch (e) {}
    window.visible = true
    refreshAll()
    Qt.callLater(function() { windowRoot.forceActiveFocus() })
  }
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "pxm")
    else close()
  }

  // ---------------------------------------------------------------- helpers
  function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  function sh(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }
  function pxDo(args) { Quickshell.execDetached([pxm].concat(args)) }
  function runSetup() {
    sh("xdg-terminal-exec bash -c " + q(q(pxm) + " setup; echo; read -rp 'Press Enter to close this window. '"))
  }
  function refreshPrefs() { if (!prefsProc.running) prefsProc.running = true }
  function flash(msg) { toast = msg; toastTimer.restart() }
  function copy(text, what) { Quickshell.execDetached(["wl-copy", String(text)]); flash((what || "Text") + " copied") }
  function tilde(p) { return String(p || "").replace(home, "~") }
  function refresh() { if (!statusProc.running) statusProc.running = true }
  function refreshPhp() { if (!phpProc.running) phpProc.running = true }
  function refreshLogs() {
    if (!logSite && siteNames.length) logSite = siteNames[0]
    if (logSite && !logsProc.running) { logsProc.command = [pxm, "logs", logSite, "--json"]; logsProc.running = true }
  }
  function refreshAll() { refresh(); refreshPhp(); refreshPrefs(); if (section === "logs") refreshLogs() }
  function run(args, label, done) {
    if (actionProc.running) return
    busy = label || "Working…"
    actionProc.after = done || ""
    actionProc.command = [pxm].concat(args)
    actionProc.running = true
  }
  function buildStatus(spec) { var b = st.building || {}; return b[spec] !== undefined ? b[spec] : null }
  function isInstalling(m) { return (st.installing || []).indexOf(m) !== -1 }
  function hasFullBuild(m) {
    var inst = st.installed || []
    for (var i = 0; i < inst.length; i++) if (inst[i].minor === m && inst[i].kind === "full" && inst[i].active) return true
    return false
  }
  function phpLabel(v) { return v === "system" ? "System" : "PHP " + v }

  onSectionChanged: { if (section === "logs") refreshLogs(); if (section === "php") refreshPhp(); if (section === "settings") refreshPrefs() }

  Process {
    id: statusProc
    command: [root.pxm, "status", "--json"]
    stdout: StdioCollector { onStreamFinished: { try { root.st = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: phpProc
    command: [root.pxm, "php", "info", "--json"]
    stdout: StdioCollector { onStreamFinished: { try { root.phpInfo = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: prefsProc
    command: [root.pxm, "prefs", "--json"]
    stdout: StdioCollector { onStreamFinished: { try { root.prefs = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: logsProc
    stdout: StdioCollector { onStreamFinished: { try { root.logData = JSON.parse(text) } catch (e) {} } }
  }
  Process {
    id: actionProc
    property string after: ""
    stdout: StdioCollector { onStreamFinished: { var t = String(text).trim(); if (t !== "") root.flash(t.split("\n").pop()) } }
    stderr: StdioCollector { onStreamFinished: { var t = String(text).trim(); if (t !== "") root.flash(t.split("\n").pop()) } }
    onExited: {
      root.busy = ""
      root.svcBusy = ""
      root.shareBusy = ""
      root.refresh()
      if (after === "php") root.refreshPhp()
      if (after === "logs") root.refreshLogs()
      if (after === "prefs") root.refreshPrefs()
    }
  }
  Timer {
    interval: 3000
    running: window.visible
    repeat: true
    onTriggered: { root.refresh(); if (root.section === "settings") root.refreshPrefs() }
  }
  Timer { id: toastTimer; interval: 2600; onTriggered: root.toast = "" }

  // ---------------------------------------------------------------- window
  FloatingWindow {
    id: window
    title: "pxm"
    color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 1)
    implicitWidth: 1000
    implicitHeight: 680
    minimumSize: Qt.size(820, 540)
    onVisibleChanged: if (!visible && !root.closingFromHost) root.requestClose()

    Item {
      id: windowRoot
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.requestClose()

      // ---------------- sidebar
      Rectangle {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(200)
        color: root.sidebarBg
        Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: root.line }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(4)

          Row {
            spacing: Style.space(10)
            bottomPadding: Style.space(14)
            Text { textFormat: Text.PlainText; text: root.snake; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              Text { textFormat: Text.PlainText; text: "pxm"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
              Text { textFormat: Text.PlainText; text: root.ready ? "PHP " + (root.st.global_full || "…") : "not set up yet"; color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption }
            }
          }

          Repeater {
            model: root.sections
            Rectangle {
              required property var modelData
              width: parent.width
              height: Style.space(36)
              radius: Style.cornerRadius
              color: root.section === modelData.id ? Style.selectedFillFor(root.fg, root.accent)
                     : (navHover.hovered ? Style.hoverFillFor(root.fg, root.accent) : "transparent")
              HoverHandler { id: navHover }
              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)
                Text { textFormat: Text.PlainText; text: modelData.icon; width: Style.space(18); color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body }
                Text { textFormat: Text.PlainText; text: modelData.label; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: root.section === modelData.id }
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.section = modelData.id }
            }
          }
        }

        Text { textFormat: Text.PlainText;
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(16)
          wrapMode: Text.WordWrap
          text: root.busy !== "" ? root.busy : (root.siteList.length + " site" + (root.siteList.length === 1 ? "" : "s") + " · " + (root.st.services || []).filter(function(s) { return s.up }).length + " services running")
          color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
        }
      }

      // ---------------- content
      ScrollView {
        id: scroll
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        contentWidth: availableWidth
        clip: true

        Loader {
          width: scroll.availableWidth
          sourceComponent: !root.ready ? setupPage : root.section === "php" ? phpPage : root.section === "services" ? servicesPage
                           : root.section === "mail" ? mailPage : root.section === "logs" ? logsPage
                           : root.section === "settings" ? settingsPage : root.section === "node" ? nodePage : sitesPage
        }
      }

      // ---------------- close button
      PanelActionButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(12)
        z: 10
        iconText: "\uf00d"
        tooltipText: "Close (Esc)"
        foreground: root.fg
        fontFamily: root.ff
        onClicked: root.requestClose()
      }

      // ---------------- toast
      Rectangle {
        visible: root.toast !== ""
        anchors.horizontalCenter: scroll.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(18)
        width: toastText.implicitWidth + Style.space(28)
        height: toastText.implicitHeight + Style.space(14)
        radius: Style.cornerRadius
        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.95)
        border.color: root.line
        Text { textFormat: Text.PlainText; id: toastText; anchors.centerIn: parent; text: root.toast; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption }
      }
    }
  }

  // ================================================================ pages
  // ---------------------------------------------------------------- Setup (before `pxm setup` has run)
  Component {
    id: setupPage
    Column {
      padding: Style.space(24)
      spacing: Style.space(14)
      width: parent ? parent.width : 0
      readonly property real inner: width - padding * 2

      Text { textFormat: Text.PlainText; text: "Welcome to pxm"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "pxm needs a one-time setup. It installs the web server, gives every folder in your sites folder an https://<folder>.test address with a trusted certificate, and downloads the latest PHP. It asks which sites folder to use, and for your password once."
        color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body
      }
      Button {
        text: "Run setup"; iconText: "\uf013"; bordered: true; foreground: root.fg; fontFamily: root.ff
        onClicked: root.runSetup()
      }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "Or run this in a terminal:  " + root.tilde(root.pxm) + " setup"
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }
    }
  }

  // ---------------------------------------------------------------- Sites
  Component {
    id: sitesPage
    Column {
      padding: Style.space(24)
      spacing: Style.space(14)
      width: parent ? parent.width : 0
      readonly property real inner: width - padding * 2

      Text { textFormat: Text.PlainText; text: "Sites"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "Every folder in " + root.tilde(root.st.sites_dir) + " is served at https://<folder>.test. You can also link any other folder."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }
      Flow {
        width: parent.inner
        spacing: Style.space(8)
        Button {
          text: "New Laravel site…"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
          onClicked: { root.creatingSite = !root.creatingSite; if (root.creatingSite) Qt.callLater(function() { newName.forceActiveFocus() }) }
        }
        Button {
          text: "Link a folder…"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
          onClicked: root.sh("d=$(omarchy-file-select --title 'Link a folder as a .test site' --directory) && [ -n \"$d\" ] && " + root.q(root.pxm) + " link \"$(basename \"$d\")\" \"$d\"")
        }
        Button {
          text: "Open sites folder"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
          onClicked: root.pxDo(["files", root.st.sites_dir])
        }
      }
      Row {
        visible: root.creatingSite
        spacing: Style.space(8)
        TextField {
          id: newName
          width: Style.space(260)
          placeholderText: "site name, e.g. blog"
          foreground: root.fg; accent: root.accent
          font.family: root.ff; font.pixelSize: Style.font.body
          onAccepted: createBtn.clicked()
        }
        Button {
          id: createBtn
          height: newName.height
          text: "Create"; bordered: true; foreground: root.fg; fontFamily: root.ff
          onClicked: {
            var n = String(newName.text).toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "")
            if (!n) { root.flash("Type a name first"); return }
            root.pxDo(["term", root.st.sites_dir, "--", "bash", "-ic",
                       "if command -v laravel >/dev/null; then laravel new " + n + "; else composer create-project laravel/laravel " + n + "; fi; exec bash"])
            root.flash("Creating " + n + ".test in a terminal…")
            root.creatingSite = false
            newName.text = ""
          }
        }
        Text { textFormat: Text.PlainText;
          anchors.verticalCenter: parent.verticalCenter
          text: "opens a terminal running `laravel new`"
          color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
        }
      }

      Text { textFormat: Text.PlainText;
        visible: root.siteList.length === 0
        text: "No sites yet."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.body
      }

      Repeater {
        model: root.siteList
        Rectangle {
          id: siteCard
          required property var modelData
          width: parent.inner
          height: siteCol.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: root.card
          border.color: root.line

          Column {
            id: siteCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(8)

            Row {
              spacing: Style.space(10)
              Text { textFormat: Text.PlainText;
                text: (siteCard.modelData.secure ? "  " : "  ") + siteCard.modelData.name + ".test"
                color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pxDo(["open", siteCard.modelData.url]) }
              }
              Text { textFormat: Text.PlainText;
                text: (siteCard.modelData.laravel ? "Laravel · " : "") + siteCard.modelData.source
                color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Row {
              visible: !!siteCard.modelData.node_missing
              spacing: Style.space(10)
              Text { textFormat: Text.PlainText;
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf071  This project asks for Node " + siteCard.modelData.node_spec + " (" + siteCard.modelData.node_file + "), which isn't installed."
                color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption
              }
              Button {
                text: root.nodeInstalling(String(siteCard.modelData.node_spec).split(".")[0]) ? "Installing…" : "Install it"
                enabled: !root.nodeInstalling(String(siteCard.modelData.node_spec).split(".")[0])
                bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.run(["node", "install", siteCard.modelData.node_spec], "Installing Node " + siteCard.modelData.node_spec + "…")
              }
            }
            Text { textFormat: Text.PlainText;
              text: root.tilde(siteCard.modelData.path) + "   →   " + root.tilde(siteCard.modelData.docroot)
              color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
              width: parent.width; elide: Text.ElideMiddle
            }
            Flow {
              width: parent.width
              spacing: Style.space(10)
              Dropdown {
                width: Style.space(200)
                showLabel: false
                fontFamily: root.ff
                options: root.sitePhpChoices
                value: siteCard.modelData.php_pinned ? siteCard.modelData.php : "Global"
                onChanged: function(v) {
                  if (v === "Global") root.run(["php", "unisolate", siteCard.modelData.path], "Using global PHP…")
                  else root.run(["php", "isolate", v, siteCard.modelData.path], "Pinning " + siteCard.modelData.name + " to " + root.phpLabel(v) + "…")
                }
              }
              Dropdown {
                width: Style.space(200)
                showLabel: false
                fontFamily: root.ff
                options: root.siteNodeChoices
                value: siteCard.modelData.node_pinned ? siteCard.modelData.node_spec : "Global"
                onChanged: function(v) {
                  if (v === (siteCard.modelData.node_pinned ? siteCard.modelData.node_spec : "Global")) return
                  if (v === "Global") root.run(["node", "unisolate", siteCard.modelData.path], "Using global Node…")
                  else root.run(["node", "isolate", v, siteCard.modelData.path], "Pinning " + siteCard.modelData.name + " to Node " + v + "…")
                }
              }
              Row {
                spacing: Style.space(6)
                height: Style.spacing.controlHeight
                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: siteCard.modelData.secure
                  foreground: root.fg
                  onToggled: root.run([siteCard.modelData.secure ? "unsecure" : "secure", siteCard.modelData.name], "Updating HTTPS…")
                }
                Text { textFormat: Text.PlainText; text: "HTTPS"; anchors.verticalCenter: parent.verticalCenter; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption }
              }
              Row {
                visible: !(siteCard.modelData.share && siteCard.modelData.share.blocked)
                spacing: Style.space(6)
                height: Style.spacing.controlHeight
                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: !!(siteCard.modelData.share && siteCard.modelData.share.on)
                  busy: root.shareBusy === siteCard.modelData.name
                  interactive: root.shareBusy === ""
                  foreground: root.fg
                  onToggled: {
                    var on = !!(siteCard.modelData.share && siteCard.modelData.share.on)
                    root.shareBusy = siteCard.modelData.name
                    root.run([on ? "unshare" : "share", siteCard.modelData.name],
                             on ? "Stopping share…" : "Sharing " + siteCard.modelData.name + ".test… (about 10 s)")
                  }
                }
                Text { textFormat: Text.PlainText; text: "Share"; anchors.verticalCenter: parent.verticalCenter; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption }
              }
              Text { textFormat: Text.PlainText;
                visible: !!(siteCard.modelData.share && siteCard.modelData.share.blocked)
                height: Style.spacing.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: "Sharing is off for phpMyAdmin (it logs in as root)"
                color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
              }
            }
            Flow {
              width: parent.width
              spacing: Style.space(10)
              Button { text: "Open"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: root.pxDo(["open", siteCard.modelData.url]) }
              Button { text: "Folder"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: root.pxDo(["files", siteCard.modelData.path]) }
              Button { text: "Terminal"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: root.pxDo(["term", siteCard.modelData.path]) }
              Button { text: "Editor"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: root.pxDo(["edit", siteCard.modelData.path]) }
              Button { text: "Logs"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: { root.logSite = siteCard.modelData.name; root.section = "logs" } }
              Button {
                visible: siteCard.modelData.source === "linked"
                text: "Unlink"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.run(["unlink", siteCard.modelData.name], "Unlinking…")
              }
            }
            Rectangle {
              visible: !!(siteCard.modelData.share && siteCard.modelData.share.on)
              width: parent.width
              height: shareCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
              Column {
                id: shareCol
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(6)
                Row {
                  spacing: Style.space(10)
                  Text { textFormat: Text.PlainText;
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf0c2  Public link"
                    color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption; font.bold: true
                  }
                  TextEdit {
                    anchors.verticalCenter: parent.verticalCenter
                    readOnly: true
                    selectByMouse: true
                    text: siteCard.modelData.share ? (siteCard.modelData.share.url || "starting…") : ""
                    color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body
                  }
                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "\uf0c5"; tooltipText: "Copy link"
                    foreground: root.fg; fontFamily: root.ff
                    onClicked: root.copy(siteCard.modelData.share.url, "Link")
                  }
                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "\uf08e"; tooltipText: "Open the public link"
                    foreground: root.fg; fontFamily: root.ff
                    onClicked: root.pxDo(["open", siteCard.modelData.share.url])
                  }
                }
                Text { textFormat: Text.PlainText;
                  width: parent.width; wrapMode: Text.WordWrap
                  text: "Anyone with this link can open the site until you turn Share off. "
                        + (siteCard.modelData.share && siteCard.modelData.share.mode === "domain"
                           ? "This link stays the same every time you share this site."
                           : "You get a new link each time you share.")
                  color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
                }
                Repeater {
                  model: siteCard.modelData.share ? (siteCard.modelData.share.warnings || []) : []
                  Text { textFormat: Text.PlainText;
                    required property var modelData
                    width: shareCol.width; wrapMode: Text.WordWrap
                    text: "\uf071  " + modelData
                    color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- PHP
  Component {
    id: phpPage
    Column {
      padding: Style.space(24)
      spacing: Style.space(14)
      width: parent ? parent.width : 0
      readonly property real inner: width - padding * 2

      Text { textFormat: Text.PlainText; text: "PHP"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "The global version runs every site and the `php` command, unless a project is pinned (Sites → PHP dropdown, or `pxm php isolate`)."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }

      PanelSectionHeader { text: "GLOBAL VERSION"; foreground: root.fg; fontFamily: root.ff }
      Flow {
        width: parent.inner
        spacing: Style.space(8)
        Repeater {
          model: root.globalChoices
          Button {
            required property var modelData
            text: root.phpLabel(modelData)
            selected: modelData === root.st.global
            bordered: true; foreground: root.fg; fontFamily: root.ff
            onClicked: if (modelData !== root.st.global) root.run(["php", "use", modelData], "Switching to " + root.phpLabel(modelData) + "…", "php")
          }
        }
      }

      PanelSectionHeader { text: "INSTALLED"; foreground: root.fg; fontFamily: root.ff }
      Repeater {
        model: root.phpInfo
        Rectangle {
          id: verCard
          required property var modelData
          width: parent.inner
          height: verCol.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: root.card
          border.color: root.line
          Column {
            id: verCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(8)
            Row {
              spacing: Style.space(10)
              Text { textFormat: Text.PlainText; text: root.phpLabel(verCard.modelData.name === "system" ? "system" : verCard.modelData.label); color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true }
              Text { textFormat: Text.PlainText;
                anchors.verticalCenter: parent.verticalCenter
                text: verCard.modelData.version + " · " + (verCard.modelData.kind === "full" ? "full build" : verCard.modelData.kind === "system" ? "Arch package" : "quick download")
                      + ((verCard.modelData.name === "system" ? "system" : verCard.modelData.label) === root.st.global ? "  · global" : "")
                color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
              }
            }
            Text { textFormat: Text.PlainText;
              width: parent.width
              wrapMode: Text.WordWrap
              maximumLineCount: root.expandedExt === verCard.modelData.name ? 99 : 2
              elide: Text.ElideRight
              text: verCard.modelData.extensions.length + " extensions: " + verCard.modelData.extensions.join(", ")
              color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.expandedExt = root.expandedExt === verCard.modelData.name ? "" : verCard.modelData.name }
            }
            Flow {
              width: parent.width
              spacing: Style.space(8)
              Button {
                visible: verCard.modelData.active_minor && (verCard.modelData.name === "system" ? "system" : verCard.modelData.label) !== root.st.global
                text: "Make global"; bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.run(["php", "use", verCard.modelData.name === "system" ? "system" : verCard.modelData.label], "Switching…", "php")
              }
              Button {
                text: "Edit php.ini"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.pxDo(["edit", verCard.modelData.ini])
              }
              Button {
                visible: verCard.modelData.name !== "system"
                text: "Uninstall"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.run(["php", "uninstall", verCard.modelData.name], "Removing PHP " + verCard.modelData.version + "…", "php")
              }
            }
          }
        }
      }

      PanelSectionHeader { text: "INSTALL"; foreground: root.fg; fontFamily: root.ff }
      Repeater {
        model: root.buildingList
        Text { textFormat: Text.PlainText;
          required property var modelData
          width: parent.inner; elide: Text.ElideRight
          text: "  Building PHP " + modelData.spec + ": " + modelData.status
          color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption
        }
      }
      Text { textFormat: Text.PlainText; text: "Quick download · about a minute · no intl/sodium"; color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption }
      Flow {
        width: parent.inner; spacing: Style.space(8)
        Text { textFormat: Text.PlainText; visible: root.installable.length === 0; text: "All quick versions are installed."; color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption }
        Repeater {
          model: root.installable
          Button {
            required property var modelData
            text: root.isInstalling(modelData.minor) ? modelData.version + "…" : modelData.version
            enabled: !root.isInstalling(modelData.minor)
            bordered: true; foreground: root.fg; fontFamily: root.ff
            onClicked: root.run(["php", "install", modelData.minor], "Downloading PHP " + modelData.version + "…", "php")
          }
        }
      }
      Text { textFormat: Text.PlainText; text: "Full build · every extension incl. intl & sodium · ~5 min in the background"; color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption }
      Flow {
        width: parent.inner; spacing: Style.space(8)
        Repeater {
          model: root.st.buildable || []
          Button {
            required property var modelData
            readonly property bool running: root.buildStatus(modelData) !== null
            text: running ? modelData + " building…" : (root.hasFullBuild(modelData) ? modelData + " ✓" : modelData)
            enabled: !running
            bordered: true; foreground: root.fg; fontFamily: root.ff
            onClicked: root.run(["php", "build", modelData], "Starting build of PHP " + modelData + "…")
          }
        }
      }
      Text { textFormat: Text.PlainText; text: "Pre-releases · alphas, betas & RCs from php.net · full build"; color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption }
      Flow {
        width: parent.inner; spacing: Style.space(8)
        Text { textFormat: Text.PlainText; visible: (root.st.prereleases || []).length === 0; text: "No pre-releases right now."; color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption }
        Repeater {
          model: root.st.prereleases || []
          Button {
            required property var modelData
            readonly property bool running: root.buildStatus(modelData.version) !== null
            text: running ? modelData.version + " building…" : modelData.version
            enabled: !running
            bordered: true; foreground: root.fg; fontFamily: root.ff
            onClicked: root.run(["php", "build", modelData.version], "Starting build of PHP " + modelData.version + "…")
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- Services
  Component {
    id: servicesPage
    Column {
      padding: Style.space(24)
      spacing: Style.space(14)
      width: parent ? parent.width : 0
      readonly property real inner: width - padding * 2

      Text { textFormat: Text.PlainText; text: "Services"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "Connection details for your apps. Stopped services stay stopped after a reboot until you switch them on."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }
      Text { textFormat: Text.PlainText;
        visible: root.st.docker === false
        width: parent.inner; wrapMode: Text.WordWrap
        text: "\uf071  MySQL, PostgreSQL, Redis and Mailpit run in Docker, which isn't installed. Install it with: sudo pacman -S docker && sudo systemctl enable --now docker"
        color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.st.services || []
        Rectangle {
          id: svcCard
          required property var modelData
          width: parent.inner
          height: svcCol.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: root.card
          border.color: root.line
          Column {
            id: svcCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)
            Item {
              width: parent.width
              height: Math.max(svcTitle.implicitHeight, svcToggle.implicitHeight)
              Row {
                id: svcTitle
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)
                Text { textFormat: Text.PlainText; text: "●"; color: svcCard.modelData.up ? "#3fb950" : root.dim; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                Text { textFormat: Text.PlainText; text: svcCard.modelData.name; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true }
                Text { textFormat: Text.PlainText; text: svcCard.modelData.up ? "running" : svcCard.modelData.created === false ? "not downloaded yet" : "stopped"; color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              }
              ToggleSwitch {
                id: svcToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: svcCard.modelData.up
                busy: root.svcBusy === svcCard.modelData.id
                interactive: root.svcBusy === ""
                foreground: root.fg
                onToggled: {
                  root.svcBusy = svcCard.modelData.id
                  root.run(["service", svcCard.modelData.up ? "stop" : "start", svcCard.modelData.id],
                           svcCard.modelData.up ? "Stopping " + svcCard.modelData.name + "…"
                           : svcCard.modelData.created === false ? "Downloading " + svcCard.modelData.name + " (first time, about a minute)…"
                           : "Starting " + svcCard.modelData.name + "…")
                }
              }
            }
            Text { textFormat: Text.PlainText;
              visible: svcCard.modelData.created === false && root.svcBusy !== svcCard.modelData.id
              width: parent.width; wrapMode: Text.WordWrap
              text: "Switch it on to download it. The first start takes about a minute; after that it starts in seconds."
              color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
            }
            Repeater {
              model: svcCard.modelData.details || []
              Row {
                required property var modelData
                spacing: Style.space(10)
                Text { textFormat: Text.PlainText; text: modelData[0]; width: Style.space(110); color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                Text { textFormat: Text.PlainText; text: modelData[1]; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                PanelActionButton {
                  visible: modelData[1].indexOf("(") !== 0
                  iconText: ""; tooltipText: "Copy"
                  foreground: root.dim; fontFamily: root.ff
                  onClicked: root.copy(modelData[1], modelData[0])
                }
              }
            }
            Rectangle {
              visible: svcCard.modelData.env !== ""
              width: parent.width
              height: envText.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
              Text { textFormat: Text.PlainText;
                id: envText
                anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Style.space(8)
                text: svcCard.modelData.env
                color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption
              }
              Button {
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(6)
                text: "Copy .env"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.copy(svcCard.modelData.env, ".env lines")
              }
            }
            Button {
              visible: !!svcCard.modelData.url
              text: "Open " + (svcCard.modelData.url || ""); iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
              onClicked: root.pxDo(["open", svcCard.modelData.url])
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- Mail
  Component {
    id: mailPage
    Column {
      padding: Style.space(24)
      spacing: Style.space(14)
      width: parent ? parent.width : 0
      readonly property real inner: width - padding * 2

      Text { textFormat: Text.PlainText; text: "Mail"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "Mailpit is a local mail catcher: your apps send email to it like a normal SMTP server, nothing is ever delivered to real inboxes, and every message shows up in the Mailpit inbox in your browser. Perfect for testing password resets, notifications and newsletters."
        color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body
      }
      Row {
        spacing: Style.space(10)
        Text { textFormat: Text.PlainText; text: "●"; color: root.mailpit && root.mailpit.up ? "#3fb950" : root.dim; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
        Text { textFormat: Text.PlainText; text: root.mailpit && root.mailpit.up ? "Mailpit is running" : root.mailpit && root.mailpit.created === false ? "Mailpit isn't downloaded yet" : "Mailpit is stopped"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
        Button {
          visible: !!root.mailpit && !root.mailpit.up
          text: "Start"; bordered: true; foreground: root.fg; fontFamily: root.ff
          onClicked: root.run(["service", "start", "mailpit"], root.mailpit.created === false ? "Downloading Mailpit (first time, about a minute)…" : "Starting Mailpit…")
        }
      }

      PanelSectionHeader { text: "SMTP SETTINGS"; foreground: root.fg; fontFamily: root.ff }
      Repeater {
        model: root.mailpit ? root.mailpit.details : []
        Row {
          required property var modelData
          spacing: Style.space(10)
          Text { textFormat: Text.PlainText; text: modelData[0]; width: Style.space(110); color: root.dim; font.family: root.ff; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
          Text { textFormat: Text.PlainText; text: modelData[1]; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
          PanelActionButton {
            iconText: ""; tooltipText: "Copy"
            foreground: root.dim; fontFamily: root.ff
            onClicked: root.copy(modelData[1], modelData[0])
          }
        }
      }

      PanelSectionHeader { text: "LARAVEL .ENV"; foreground: root.fg; fontFamily: root.ff }
      Rectangle {
        width: parent.inner
        height: mailEnv.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
        Text { textFormat: Text.PlainText;
          id: mailEnv
          anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Style.space(8)
          text: root.mailpit ? root.mailpit.env : ""
          color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body
        }
        Button {
          anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(6)
          text: "Copy"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
          onClicked: root.copy(root.mailpit ? root.mailpit.env : "", "Mail settings")
        }
      }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "Paste these into your project's .env (replacing the existing MAIL_ lines), then run `php artisan config:clear` if you cache config."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }
      Flow {
        width: parent.inner
        spacing: Style.space(8)
        Button { text: "Open inbox"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: root.pxDo(["open", "http://localhost:8025"]) }
        Button { text: "Send test email"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: root.run(["mail", "test"], "Sending test email…") }
      }
    }
  }

  // ---------------------------------------------------------------- Logs
  Component {
    id: logsPage
    Column {
      padding: Style.space(24)
      spacing: Style.space(14)
      width: parent ? parent.width : 0
      readonly property real inner: width - padding * 2

      Text { textFormat: Text.PlainText; text: "Logs"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "The latest errors for a site: Laravel's log plus the PHP error log of the version that serves it. Handy when a page shows a blank 500."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }
      Flow {
        width: parent.inner
        spacing: Style.space(8)
        Dropdown {
          width: Style.space(260)
          showLabel: false
          fontFamily: root.ff
          options: root.siteNames
          value: root.logSite
          onChanged: function(v) { root.logSite = v; root.refreshLogs() }
        }
        Button { height: Style.spacing.controlHeight; text: "Refresh"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: root.refreshLogs() }
      }
      Repeater {
        model: root.logData.files || []
        Column {
          required property var modelData
          width: parent.inner
          spacing: Style.space(6)
          Row {
            spacing: Style.space(10)
            Text { textFormat: Text.PlainText; text: modelData.label; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Text { textFormat: Text.PlainText; text: root.tilde(modelData.path); color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
            PanelActionButton {
              visible: modelData.exists
              iconText: ""; tooltipText: "Open in editor"
              foreground: root.dim; fontFamily: root.ff
              onClicked: root.pxDo(["edit", modelData.path])
            }
          }
          Rectangle {
            width: parent.width
            height: Math.min(logText.implicitHeight + Style.space(16), Style.space(260))
            radius: Style.cornerRadius
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
            clip: true
            Flickable {
              id: logFlick
              anchors.fill: parent
              anchors.margins: Style.space(8)
              contentWidth: width
              contentHeight: logText.implicitHeight
              clip: true
              Component.onCompleted: contentY = Math.max(0, contentHeight - height)
              TextEdit {
                id: logText
                width: logFlick.width
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                text: modelData.text
                color: root.fg; font.family: root.ff; font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- Node
  Component {
    id: nodePage
    Column {
      padding: Style.space(24)
      spacing: Style.space(14)
      width: parent ? parent.width : 0
      readonly property real inner: width - padding * 2

      Text { textFormat: Text.PlainText; text: "Node"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "Node versions are managed by mise, the version manager Omarchy ships. Anything you do here also shows up in `mise` in the terminal, and the other way round. Terminals switch versions automatically per project."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }

      PanelSectionHeader { text: "GLOBAL VERSION"; foreground: root.fg; fontFamily: root.ff }
      Flow {
        width: parent.inner
        spacing: Style.space(8)
        Text { textFormat: Text.PlainText;
          visible: (root.node.majors || []).length === 0
          text: "No Node installed yet. Pick one under Install."
          color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
        }
        Repeater {
          model: root.node.majors || []
          Button {
            required property var modelData
            text: "Node " + modelData.major
            selected: modelData.major === root.node.global_major
            bordered: true; foreground: root.fg; fontFamily: root.ff
            onClicked: if (!selected) root.run(["node", "use", modelData.major], "Switching to Node " + modelData.major + "…")
          }
        }
      }
      Text { textFormat: Text.PlainText;
        visible: root.node.global_spec === "latest" || root.node.global_spec === "lts"
        width: parent.inner; wrapMode: Text.WordWrap
        text: root.node.global_spec === "latest"
              ? "Global is set to \"latest\": always the newest Node you have installed. Click a version to lock it instead."
              : "Global is set to \"lts\": the newest LTS Node you have installed."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }

      PanelSectionHeader { text: "INSTALLED"; foreground: root.fg; fontFamily: root.ff }
      Repeater {
        model: root.node.installed || []
        Rectangle {
          id: nodeCard
          required property var modelData
          width: parent.inner
          height: nodeCol.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: root.card
          border.color: root.line
          Column {
            id: nodeCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(8)
            Row {
              spacing: Style.space(10)
              Text { textFormat: Text.PlainText; text: "Node " + nodeCard.modelData.version; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true }
              Text { textFormat: Text.PlainText;
                anchors.verticalCenter: parent.verticalCenter
                text: (nodeCard.modelData.lts ? "LTS " + nodeCard.modelData.lts : "current release")
                      + (nodeCard.modelData.version === root.node.global ? "  · global" : "")
                color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
              }
            }
            Flow {
              width: parent.width
              spacing: Style.space(8)
              Button {
                visible: nodeCard.modelData.major !== root.node.global_major
                text: "Make global"; bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.run(["node", "use", nodeCard.modelData.major], "Switching to Node " + nodeCard.modelData.major + "…")
              }
              Button {
                visible: nodeCard.modelData.update !== ""
                text: root.nodeInstalling(nodeCard.modelData.major) ? "Updating…" : "Update to " + nodeCard.modelData.update
                iconText: ""
                enabled: !root.nodeInstalling(nodeCard.modelData.major)
                bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.run(["node", "install", nodeCard.modelData.update], "Installing Node " + nodeCard.modelData.update + "…")
              }
              Button {
                text: "Uninstall"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: root.run(["node", "uninstall", nodeCard.modelData.version], "Removing Node " + nodeCard.modelData.version + "…")
              }
            }
          }
        }
      }

      PanelSectionHeader { text: "INSTALL"; foreground: root.fg; fontFamily: root.ff }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "LTS versions get long-term support and are the safe pick for projects. \"Current\" is the newest release. Each one takes a few seconds."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }
      Flow {
        width: parent.inner
        spacing: Style.space(8)
        Text { textFormat: Text.PlainText;
          visible: (root.node.lines || []).length === 0
          text: "Couldn't reach nodejs.org to list versions."
          color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
        }
        Repeater {
          model: root.node.lines || []
          Button {
            required property var modelData
            readonly property bool installing: root.nodeInstalling(modelData.major)
            text: "Node " + modelData.major + "  ·  " + (modelData.lts ? "LTS " + modelData.lts : "current")
                  + (modelData.installed ? "  ✓" : installing ? "  …" : "")
            tooltipText: modelData.installed ? "Installed" : "Install Node " + modelData.version
            enabled: !modelData.installed && !installing
            bordered: true; foreground: root.fg; fontFamily: root.ff
            onClicked: root.run(["node", "install", modelData.major], "Installing Node " + modelData.version + "…")
          }
        }
      }

      PanelSectionHeader { text: "PROJECT VERSIONS"; foreground: root.fg; fontFamily: root.ff }
      Rectangle {
        width: parent.inner
        height: nvCol.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: root.card
        border.color: root.line
        Column {
          id: nvCol
          anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
          anchors.margins: Style.space(12)
          spacing: Style.space(8)
          Item {
            width: parent.width
            height: Math.max(nvTitle.implicitHeight, nvToggle.implicitHeight)
            Text { textFormat: Text.PlainText;
              id: nvTitle
              anchors.verticalCenter: parent.verticalCenter
              text: "Follow .nvmrc / .node-version files"
              color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true
            }
            ToggleSwitch {
              id: nvToggle
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: !!root.node.nvmrc
              foreground: root.fg
              onToggled: root.run(["node", "nvmrc", root.node.nvmrc ? "off" : "on"], "Saving…")
            }
          }
          Text { textFormat: Text.PlainText;
            width: parent.width; wrapMode: Text.WordWrap
            text: "Many projects say which Node they need in a .nvmrc file. With this on, a terminal opened in that project uses that version automatically. Pick a version per site on the Sites page: pxm writes the .nvmrc for you."
            color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- Settings
  Component {
    id: settingsPage
    Column {
      padding: Style.space(24)
      spacing: Style.space(14)
      width: parent ? parent.width : 0
      readonly property real inner: width - padding * 2

      Text { textFormat: Text.PlainText; text: "Settings"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.title; font.bold: true }
      Text { textFormat: Text.PlainText;
        width: parent.inner; wrapMode: Text.WordWrap
        text: "Which apps pxm opens things with. \"System default\" follows Omarchy's own setting, so it changes when you change Omarchy's default. Only apps installed on this laptop are listed."
        color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.prefKinds
        Rectangle {
          id: prefCard
          required property var modelData
          readonly property var pref: root.prefs[modelData.id] || ({ value: "system", custom: "", options: [] })
          width: parent.inner
          height: prefCol.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: root.card
          border.color: root.line
          Column {
            id: prefCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)
            Text { textFormat: Text.PlainText; text: prefCard.modelData.title; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true }
            Text { textFormat: Text.PlainText; text: prefCard.modelData.hint; width: parent.width; wrapMode: Text.WordWrap; color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption }
            Flow {
              width: parent.width
              spacing: Style.space(10)
              Dropdown {
                width: Style.space(300)
                showLabel: false
                fontFamily: root.ff
                options: prefCard.pref.options
                value: prefCard.pref.value
                onChanged: function(v) {
                  if (v === prefCard.pref.value) return
                  root.run(["prefs", "set", prefCard.modelData.id, v], "Saving…", "prefs")
                }
              }
              Button {
                height: Style.spacing.controlHeight
                text: "Try it"; iconText: ""; bordered: true; foreground: root.fg; fontFamily: root.ff
                onClicked: {
                  var k = prefCard.modelData.id
                  if (k === "browser") root.pxDo(["open", root.siteList.length ? root.siteList[0].url : "http://localhost:8025"])
                  else root.pxDo([k === "editor" ? "edit" : k === "terminal" ? "term" : "files", root.st.sites_dir])
                }
              }
            }
            Column {
              visible: prefCard.pref.value === "custom"
              width: parent.width
              spacing: Style.space(6)
              Row {
                spacing: Style.space(8)
                TextField {
                  id: customField
                  width: Style.space(380)
                  text: prefCard.pref.custom
                  placeholderText: prefCard.modelData.id === "browser" ? "e.g. firefox --new-window {path}" : "e.g. phpstorm {path}"
                  foreground: root.fg; accent: root.accent
                  font.family: root.ff; font.pixelSize: Style.font.body
                  onAccepted: saveCustom.clicked()
                }
                Button {
                  id: saveCustom
                  height: customField.height
                  text: "Save"; bordered: true; foreground: root.fg; fontFamily: root.ff
                  onClicked: root.run(["prefs", "set", prefCard.modelData.id, "custom", String(customField.text)], "Saving…", "prefs")
                }
              }
              Text { textFormat: Text.PlainText;
                width: parent.width; wrapMode: Text.WordWrap
                text: "{path} is replaced by the folder or file (the address, for the browser). If you leave it out, it's added at the end."
                color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      Rectangle {
        width: parent.inner
        height: shareSetCol.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: root.card
        border.color: root.line
        Column {
          id: shareSetCol
          anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
          anchors.margins: Style.space(12)
          spacing: Style.space(10)
          Text { textFormat: Text.PlainText; text: "Sharing links"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.body; font.bold: true }
          Text { textFormat: Text.PlainText;
            width: parent.width; wrapMode: Text.WordWrap
            text: root.st.share_domain
                  ? "Shared sites get https://<site>." + root.st.share_domain + " (always the same link per site), through your Cloudflare account."
                  : "Shared sites get a random https://….trycloudflare.com link, new each time. Connect a domain from your Cloudflare account to get fixed links like https://<site>.yourdomain.com."
            color: root.dim; font.family: root.ff; font.pixelSize: Style.font.caption
          }
          Button {
            visible: !!root.st.share_domain
            height: Style.spacing.controlHeight
            text: "Use random links instead"; bordered: true; foreground: root.fg; fontFamily: root.ff
            onClicked: root.run(["share", "domain", "off"], "Switching to random links…")
          }
          Row {
            visible: !root.st.share_domain
            spacing: Style.space(8)
            TextField {
              id: domainField
              width: Style.space(300)
              placeholderText: "yourdomain.com"
              foreground: root.fg; accent: root.accent
              font.family: root.ff; font.pixelSize: Style.font.body
              onAccepted: connectDomain.clicked()
            }
            Button {
              id: connectDomain
              height: domainField.height
              text: "Connect"; bordered: true; foreground: root.fg; fontFamily: root.ff
              onClicked: {
                var d = String(domainField.text).trim()
                if (!d) { root.flash("Type your domain first"); return }
                root.run(["share", "domain", d], "Connecting " + d + "… (if a browser tab opens, pick the domain and click Authorize)")
              }
            }
          }
        }
      }
    }
  }
}
