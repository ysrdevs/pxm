import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// pxm in the bar: PHP and Node versions, *.test sites, sharing and services at a glance.
// All state comes from `pxm status --json`; all actions call the pxm CLI that ships in this plugin (bin/pxm).
Panel {
  id: root
  moduleName: "pxm"
  ipcTarget: "pxm"

  readonly property string pxm: decodeURIComponent(Qt.resolvedUrl("bin/pxm").toString().replace(/^file:\/\//, ""))
  readonly property bool ready: st.ready !== false
  property var st: ({ global: "", global_full: "", system: "", installed: [], available: [], installing: [],
                      sites: ({}), services: [], trusted: true, caddy: "" })
  property bool showInstall: false
  property bool showNodeInstall: false
  readonly property var node: st.node || ({ majors: [], lines: [], installing: [], global_major: "", global: "" })
  function nodeInstalling(major) { return (node.installing || []).indexOf(major) !== -1 }
  property string busy: ""
  property string svcBusy: ""
  property string shareBusy: ""
  readonly property var sharedList: siteList.filter(function(s) { return s.share && s.share.on })

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string pxIcon: "\uDB85\uDD0E"   // nf-md-snake (Slytherin vibes)
  readonly property string phpIcon: pxIcon         // also used in notifications
  readonly property color badgeInk: {
    var bg = root.bar ? root.bar.background : Color.bar.background
    return bg.a < 0.5 ? "#000000" : bg
  }

  readonly property var siteList: {
    var out = []
    var s = st.sites || {}
    for (var k in s) out.push(Object.assign({ name: k }, s[k]))
    return out
  }
  readonly property var versionList: {
    var out = st.system ? [{ key: "system", label: "System", detail: st.system + "  ·  Arch package" }] : []
    for (var i = 0; i < (st.installed || []).length; i++) {
      var v = st.installed[i]
      if (v.active) out.push({ key: v.minor, label: "PHP " + v.minor, detail: v.version + (v.kind === "full" ? " · full build" : " · quick download") })
    }
    return out
  }
  readonly property var installable: {
    var out = []
    for (var i = 0; i < (st.available || []).length; i++)
      if (!st.available[i].installed) out.push(st.available[i])
    return out
  }

  function refresh() { if (!statusProc.running) statusProc.running = true }
  function act(args, label) {
    if (actionProc.running) return
    busy = label || "Working…"
    actionProc.command = [pxm].concat(args)
    actionProc.running = true
  }
  function launch(cmd) { if (root.bar) root.bar.run(cmd) }
  function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  function isInstalling(minor) { return (st.installing || []).indexOf(minor) !== -1 }
  function buildStatus(spec) { var b = st.building || {}; return b[spec] !== undefined ? b[spec] : null }
  readonly property var buildingList: {
    var out = []
    var b = st.building || {}
    for (var k in b) out.push({ spec: k, status: b[k] })
    return out
  }
  function hasFullBuild(minor) {
    var inst = st.installed || []
    for (var i = 0; i < inst.length; i++) if (inst[i].minor === minor && inst[i].kind === "full" && inst[i].active) return true
    return false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: [root.pxm, "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.st = JSON.parse(text) } catch (e) {} }
    }
  }
  Process {
    id: actionProc
    stderr: StdioCollector {
      onStreamFinished: if (String(text).trim() !== "") root.launch("omarchy-notification-send -g " + root.q(root.phpIcon) + " 'pxm' " + root.q(String(text).trim()))
    }
    onExited: { root.busy = ""; root.svcBusy = ""; root.shareBusy = ""; root.refresh() }
  }
  Timer {
    interval: root.opened || (root.st.installing || []).length > 0 || root.buildingList.length > 0 || (root.node.installing || []).length > 0 ? 2500 : 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  onOpenedChanged: if (opened) { showInstall = false; showNodeInstall = false; refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pxIcon
    tooltipText: root.opened ? "" : !root.ready ? "pxm: click to finish setting up" : ("PHP " + (root.st.global_full || "…") + (root.node.global ? "  ·  Node " + root.node.global : "") + "  ·  " + root.siteList.length + " site" + (root.siteList.length === 1 ? "" : "s"))
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(root.ready ? column.implicitHeight : setupColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // ---------------- not set up yet ----------------
      Column {
        id: setupColumn
        visible: !root.ready
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "pxm"
          meta: "One-time setup needed"
          detail: "Sets up *.test sites with HTTPS, PHP and the web server. Asks for your password once."
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text { text: root.pxIcon; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.display }
          }
        }
        Button {
          width: parent.width
          text: "Set up pxm"
          iconText: "\uf013"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: {
            root.close()
            root.launch("xdg-terminal-exec bash -c " + root.q(root.q(root.pxm) + " setup; echo; read -rp 'Press Enter to close this window. '"))
          }
        }
      }

      Column {
        id: column
        visible: root.ready
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------------- hero ----------------
        PanelHero {
          width: parent.width
          title: "PHP " + (root.st.global_full || "")
          meta: root.busy !== "" ? root.busy
                : (root.st.global === "system" ? "Global: System PHP (Arch package)" : "Global PHP via pxm")
          detail: root.siteList.length + " site" + (root.siteList.length === 1 ? "" : "s") + " in " + String(root.st.sites_dir || "").replace(Quickshell.env("HOME"), "~")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text { text: root.pxIcon; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.display }
          }
        }

        Button {
          width: parent.width
          text: "Open pxm"
          iconText: "\uf2d0"
          tooltipText: "Sites, PHP, services, mail settings and logs"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: { root.close(); root.launch(root.q(root.pxm) + " ui") }
        }

        // ---------------- PHP versions ----------------
        PanelSectionHeader { text: "PHP VERSION"; foreground: root.foreground; fontFamily: root.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.versionList
            Button {
              required property var modelData
              text: modelData.label
              tooltipText: modelData.key === root.st.global ? "Global PHP (" + modelData.detail + ")" : "Make " + modelData.label + " global (" + modelData.detail + ")"
              selected: modelData.key === root.st.global
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (modelData.key !== root.st.global) root.act(["php", "use", modelData.key], "Switching to " + modelData.label + "…")
            }
          }
          Button {
            text: root.showInstall ? "Hide" : "Install…"
            iconSize: Style.font.body
            iconText: root.showInstall ? "" : ""
            tooltipText: "Download another PHP version"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.showInstall = !root.showInstall
          }
        }

        // builds in progress (always visible)
        Repeater {
          model: root.buildingList
          Text {
            required property var modelData
            width: column.width
            elide: Text.ElideRight
            text: "  Building PHP " + modelData.spec + ": " + modelData.status
            color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
        }

        Column {
          visible: root.showInstall
          width: parent.width
          spacing: Style.space(6)

          // quick downloads
          Text {
            text: "QUICK DOWNLOAD  ·  about a minute  ·  no intl/sodium"
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Text {
              visible: root.installable.length === 0
              text: "All quick versions are installed."
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
            Repeater {
              model: root.installable
              Button {
                required property var modelData
                text: root.isInstalling(modelData.minor) ? modelData.version + "…" : modelData.version
                tooltipText: "Download PHP " + modelData.version
                enabled: !root.isInstalling(modelData.minor)
                bordered: true
                foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: root.launch(root.q(root.pxm) + " php install " + modelData.minor + " && omarchy-notification-send -g " + root.q(root.phpIcon) + " 'PHP " + modelData.version + " installed'")
              }
            }
          }

          // full builds
          Text {
            text: "FULL BUILD  ·  every extension incl. intl & sodium  ·  ~5 min in background"
            width: parent.width; wrapMode: Text.WordWrap
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.st.buildable || []
              Button {
                required property var modelData
                readonly property bool running: root.buildStatus(modelData) !== null
                text: running ? modelData + " building…" : (root.hasFullBuild(modelData) ? modelData + " ✓" : modelData)
                tooltipText: root.hasFullBuild(modelData) ? "Rebuild the latest " + modelData + " (full)" : "Build the latest PHP " + modelData + " with all extensions"
                enabled: !running
                bordered: true
                foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: root.act(["php", "build", modelData], "Starting build of PHP " + modelData + "…")
              }
            }
          }

          // pre-releases
          Text {
            text: "PRE-RELEASES  ·  alphas, betas & RCs from php.net  ·  full build"
            width: parent.width; wrapMode: Text.WordWrap
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Text {
              visible: (root.st.prereleases || []).length === 0
              text: "No pre-releases right now."
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
            Repeater {
              model: root.st.prereleases || []
              Button {
                required property var modelData
                readonly property bool running: root.buildStatus(modelData.version) !== null
                text: running ? modelData.version + " building…" : modelData.version
                tooltipText: "Build PHP " + modelData.version + " (released " + modelData.date + ")"
                enabled: !running
                bordered: true
                foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: root.act(["php", "build", modelData.version], "Starting build of PHP " + modelData.version + "…")
              }
            }
          }
        }

        // ---------------- Node versions ----------------
        PanelSectionHeader { text: "NODE VERSION"; foreground: root.foreground; fontFamily: root.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Text {
            visible: (root.node.majors || []).length === 0
            text: "No Node yet."
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.node.majors || []
            Button {
              required property var modelData
              text: "Node " + modelData.major
              tooltipText: (modelData.major === root.node.global_major ? "Global Node (" : "Make Node " + modelData.major + " global (")
                           + modelData.version + (modelData.lts ? ", LTS " + modelData.lts : "") + ")"
              selected: modelData.major === root.node.global_major
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (!selected) root.act(["node", "use", modelData.major], "Switching to Node " + modelData.major + "…")
            }
          }
          Button {
            text: root.showNodeInstall ? "Hide" : "Install…"
            iconSize: Style.font.body
            iconText: root.showNodeInstall ? "" : ""
            tooltipText: "Download another Node version"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.showNodeInstall = !root.showNodeInstall
          }
        }

        Flow {
          visible: root.showNodeInstall
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.node.lines || []
            Button {
              required property var modelData
              readonly property bool installing: root.nodeInstalling(modelData.major)
              text: "Node " + modelData.major + (modelData.lts ? " LTS" : "") + (modelData.installed ? " ✓" : installing ? "…" : "")
              tooltipText: modelData.installed ? "Node " + modelData.major + " is installed"
                           : "Install Node " + modelData.version + (modelData.lts ? " (LTS " + modelData.lts + ")" : " (current)")
              enabled: !modelData.installed && !installing
              bordered: true
              foreground: root.foreground; fontFamily: root.fontFamily
              onClicked: root.launch(root.q(root.pxm) + " node install " + modelData.major + " >/dev/null && omarchy-notification-send -g " + root.q(root.phpIcon) + " 'Node " + modelData.version + " installed'")
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        // ---------------- sites ----------------
        PanelSectionHeader { text: "SITES"; foreground: root.foreground; fontFamily: root.fontFamily }

        Text {
          visible: root.siteList.length === 0
          width: parent.width
          wrapMode: Text.WordWrap
          text: "No sites yet. Every folder in " + String(root.st.sites_dir || "").replace(Quickshell.env("HOME"), "~") + " becomes https://<folder>.test."
          color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.siteList
          Rectangle {
            id: siteRow
            required property var modelData
            width: column.width
            height: Style.space(34)
            radius: Style.cornerRadius
            color: rowHover.hovered ? root.hoverFill : "transparent"
            HoverHandler { id: rowHover }

            Row {
              id: siteLeft
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: siteRow.width - siteActions.width - Style.space(16)
              spacing: Style.space(8)
              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconText: siteRow.modelData.secure ? "" : ""
                tooltipText: siteRow.modelData.secure ? "HTTPS on (click for plain http)" : "HTTPS off (click to secure)"
                foreground: siteRow.modelData.secure ? root.foreground : root.dim
                fontFamily: root.fontFamily
                onClicked: root.act([siteRow.modelData.secure ? "unsecure" : "secure", siteRow.modelData.name], "Updating " + siteRow.modelData.name + ".test…")
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: siteRow.modelData.name + ".test"
                color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.launch(root.q(root.pxm) + " open " + root.q(siteRow.modelData.url)); root.close() }
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.max(0, siteLeft.width - x))
                elide: Text.ElideRight
                text: "PHP " + (siteRow.modelData.php === "system" ? "system" : siteRow.modelData.php) + (siteRow.modelData.php_pinned ? " 󰐃" : "")
                      + (siteRow.modelData.node_missing ? " · Node " + siteRow.modelData.node_spec + " missing"
                         : siteRow.modelData.node ? " · Node " + String(siteRow.modelData.node).split(".")[0] + (siteRow.modelData.node_pinned ? " 󰐃" : "") : "")
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
            }
            Row {
              id: siteActions
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              PanelActionButton {
                readonly property bool shared: !!(siteRow.modelData.share && siteRow.modelData.share.on)
                visible: !(siteRow.modelData.share && siteRow.modelData.share.blocked)
                iconText: root.shareBusy === siteRow.modelData.name ? "\uf110" : shared ? "\uf0c2" : "\uf1e0"
                tooltipText: shared ? "Shared publicly: click to stop" : "Share publicly (a link anyone can open)"
                foreground: shared ? root.foreground : root.dim
                fontFamily: root.fontFamily
                onClicked: {
                  if (root.shareBusy !== "") return
                  root.shareBusy = siteRow.modelData.name
                  root.act([shared ? "unshare" : "share", siteRow.modelData.name],
                           shared ? "Stopping share…" : "Sharing " + siteRow.modelData.name + ".test… (about 10 s)")
                }
              }
              PanelActionButton {
                iconText: ""; tooltipText: "Open " + siteRow.modelData.url
                foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: { root.launch(root.q(root.pxm) + " open " + root.q(siteRow.modelData.url)); root.close() }
              }
              PanelActionButton {
                iconText: ""; tooltipText: "Terminal in this folder"
                foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: { root.launch(root.q(root.pxm) + " term " + root.q(siteRow.modelData.path)); root.close() }
              }
              PanelActionButton {
                iconText: ""; tooltipText: "Open folder"
                foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: { root.launch(root.q(root.pxm) + " files " + root.q(siteRow.modelData.path)); root.close() }
              }
              PanelActionButton {
                visible: siteRow.modelData.source === "linked"
                iconText: ""; tooltipText: "Unlink (stop serving this folder)"
                foreground: root.dim; fontFamily: root.fontFamily
                onClicked: root.act(["unlink", siteRow.modelData.name], "Unlinking…")
              }
            }
          }
        }

        // ---------------- sharing now ----------------
        Column {
          visible: root.sharedList.length > 0
          width: parent.width
          spacing: Style.space(6)
          Text {
            text: "SHARING NOW  ·  anyone with the link can open it"
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.sharedList
            Column {
              id: shareRow
              required property var modelData
              width: column.width
              spacing: Style.space(2)
              Item {
                width: parent.width
                height: Style.space(30)
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.right: shareBtns.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideMiddle
                  text: shareRow.modelData.name + ".test  \u2192  " + (shareRow.modelData.share.url || "starting…")
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
                Row {
                  id: shareBtns
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  PanelActionButton {
                    iconText: "\uf0c5"; tooltipText: "Copy link"
                    foreground: root.foreground; fontFamily: root.fontFamily
                    onClicked: root.launch("wl-copy " + root.q(shareRow.modelData.share.url) + " && omarchy-notification-send -g "
                                           + root.q(root.phpIcon) + " 'Link copied' " + root.q(shareRow.modelData.share.url))
                  }
                  PanelActionButton {
                    iconText: "\uf08e"; tooltipText: "Open the public link"
                    foreground: root.foreground; fontFamily: root.fontFamily
                    onClicked: { root.launch(root.q(root.pxm) + " open " + root.q(shareRow.modelData.share.url)); root.close() }
                  }
                  PanelActionButton {
                    iconText: "\uf04d"; tooltipText: "Stop sharing"
                    foreground: root.foreground; fontFamily: root.fontFamily
                    onClicked: { root.shareBusy = shareRow.modelData.name; root.act(["unshare", shareRow.modelData.name], "Stopping share…") }
                  }
                }
              }
              Repeater {
                model: shareRow.modelData.share.warnings || []
                Text {
                  required property var modelData
                  width: shareRow.width - Style.space(12)
                  x: Style.space(6)
                  wrapMode: Text.WordWrap
                  text: "\uf071  " + modelData
                  color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Button {
            text: "Sites folder"; iconText: ""; bordered: true
            foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: { root.launch(root.q(root.pxm) + " files " + root.q(root.st.sites_dir)); root.close() }
          }
          Button {
            text: "Link a folder…"; iconText: ""; bordered: true
            tooltipText: "Serve any folder as https://<name>.test"
            foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: {
              root.close()
              root.launch("d=$(omarchy-file-select --title 'Link a folder as a .test site' --directory) && [ -n \"$d\" ] && "
                          + root.q(root.pxm) + " link \"$(basename \"$d\")\" \"$d\" >/dev/null && omarchy-notification-send -g "
                          + root.q(root.phpIcon) + " \"Linked $(basename \"$d\").test\"")
            }
          }
        }

        Text {
          visible: !root.st.trusted
          width: parent.width
          wrapMode: Text.WordWrap
          text: "HTTPS certificate not trusted yet. Run: pxm trust"
          color: root.bar ? root.bar.urgent : Color.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        // ---------------- services ----------------
        PanelSectionHeader { text: "SERVICES"; foreground: root.foreground; fontFamily: root.fontFamily }

        Repeater {
          model: root.st.services || []
          Item {
            required property var modelData
            width: column.width
            height: Style.space(24)
            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "●"
                color: modelData.up ? "#3fb950" : root.dim
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData.up ? "running" : "stopped") + " · :" + modelData.port
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              PanelActionButton {
                visible: !!modelData.url && modelData.up
                anchors.verticalCenter: parent.verticalCenter
                iconText: "\uf08e"; tooltipText: "Open " + (modelData.url || "")
                foreground: root.foreground; fontFamily: root.fontFamily
                onClicked: { root.launch(root.q(root.pxm) + " open " + root.q(modelData.url)); root.close() }
              }
              ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: modelData.up
                busy: root.svcBusy === modelData.id
                interactive: root.svcBusy === ""
                foreground: root.foreground
                onToggled: {
                  root.svcBusy = modelData.id
                  root.act(["service", modelData.up ? "stop" : "start", modelData.id],
                           (modelData.up ? "Stopping " : "Starting ") + modelData.name + "…")
                }
              }
            }
          }
        }
      }
    }
  }
}
