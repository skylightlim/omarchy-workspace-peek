import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // Settings (inline entry in shell.json):
  //   showAppIcons   - show the biggest window's icon on occupied workspaces
  //   monochromeIcons- tint icons with the bar foreground color
  //   iconScale      - icon size multiplier
  //   revealDelay    - how long Super must be held before numbers appear (ms)
  //   iconOverrides  - escape hatch for a TUI app whose process name differs
  //                    from its icon name, e.g. [{"process":"nvim",
  //                    "icon":"icons/neovim.png"}]. Most apps need no entry:
  //                    see the resolution order below. Icon paths resolve
  //                    relative to this plugin's directory.
  readonly property bool showAppIcons: setting("showAppIcons", true)
  readonly property bool monochromeIcons: setting("monochromeIcons", true)
  readonly property real iconScale: Number(setting("iconScale", 1.0)) || 1.0
  readonly property int iconSize: Math.max(8, Math.round(Style.space(14) * root.iconScale))
  readonly property real revealDelay: Number(setting("revealDelay", 100))
  readonly property var iconOverrides: normalizeIconOverrides(setting("iconOverrides", []))

  // Zero-config icon discovery. A detected TUI process resolves to an icon by,
  // in order: an explicit iconOverrides entry; a file in this plugin's icons/
  // directory named after the process ("claude" -> icons/claude.png), which is
  // all that shipping support for a new app takes; then the system icon theme,
  // where btop, nvim, vim, htop and docker already resolve with nothing
  // bundled at all.
  //
  // Shells and multiplexers are deliberately absent from this list: the probe
  // takes the FIRST match in the process tree, so listing tmux or bash would
  // shadow whatever is actually running inside them.
  readonly property var knownTuiApps: [
    "btop", "htop", "glances", "bpytop", "ncdu", "dust", "duf",
    "nvim", "vim", "helix", "hx", "emacs", "nano", "micro",
    "yazi", "ranger", "nnn", "lf", "mc", "broot",
    "lazygit", "gitui", "tig", "lazydocker", "k9s", "kubectl",
    "claude", "opencode", "aider", "codex", "crush", "goose",
    "cava", "cmus", "ncmpcpp", "newsboat", "neomutt", "mutt",
    "irssi", "weechat", "calcurse", "taskwarrior", "btm", "bandwhich"
  ]

  // Basenames (lowercased, extension stripped) of files in icons/ -> filename.
  property var bundledIcons: ({})

  readonly property var appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
  readonly property color foreground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color iconForeground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property bool isLightTheme: {
    var c = root.bar ? root.bar.background : Color.background
    var col = Qt.color(c)
    return (col.r * 0.299 + col.g * 0.587 + col.b * 0.114) > 0.5
  }
  readonly property bool tintIcons: root.monochromeIcons && !(root.bar ? root.bar.transparent : false) && !root.isLightTheme

  // Quickshell.Hyprland exposes the workspace/toplevel collections as CONSTANT
  // object models, so QML bindings cannot see them mutate. The slot delegates
  // are created before the initial Hyprland sync populates the workspace list,
  // and without a reactive dependency they would stay stuck on empty
  // workspaces (numbers instead of icons). Bumping syncToken on relevant IPC
  // events re-evaluates the per-slot workspace/occupancy bindings.
  property int syncToken: 0
  function bumpSync() {
    root.syncToken++
  }

  // ------------------------------------------------- terminal app icons
  // TUI apps (yazi, btop, lazygit, ...) run inside a terminal, so window
  // class/title alone never identify them. For every iconOverrides entry,
  // each workspace's biggest window is probed by scanning its process tree;
  // a match swaps in that app's custom icon. Results are cached per window
  // pid and re-probed on a timer, so icons follow app start/stop without
  // depending on window events.
  //
  // Quickshell only fills a toplevel's lastIpcObject during the initial sync,
  // so windows opened after the shell started have no pid/size there. Every
  // cycle we therefore fetch `hyprctl clients -j` and match toplevels by
  // their hex address (tl.address lacks the "0x" prefix, hyprctl has it),
  // giving live pid and area for all windows.
  property var probeCache: ({})    // window pid -> override icon path ("" = probed, no match)
  property int probeTick: 0        // bumped per result so bindings re-evaluate
  property var probeQueue: []      // pids waiting for their pstree scan
  property int probeBusyPid: 0     // pid whose scan is currently running
  property var clientInfo: ({})    // address ("0x...") -> {pid, area}

  // Every process name the probe regex should look for: explicit overrides,
  // whatever is bundled in icons/, and the curated defaults. Sanitized to
  // [a-z0-9_-] so a name can never break the ERE it is spliced into.
  function probeNames() {
    var seen = {}
    var out = []
    function add(raw) {
      var n = String(raw || "").toLowerCase().replace(/[^a-z0-9_-]/g, "")
      if (!n || seen[n]) return
      seen[n] = true
      out.push(n)
    }
    for (var i = 0; i < root.iconOverrides.length; i++) add(root.iconOverrides[i].process)
    for (var key in root.bundledIcons) add(key)
    for (var j = 0; j < root.knownTuiApps.length; j++) add(root.knownTuiApps[j])
    return out
  }

  // Matched process name -> icon source, walking the three tiers. Returns ""
  // when nothing claims it, which leaves the slot on the terminal's own icon.
  function resolveProcessIcon(name) {
    if (!name) return ""
    for (var i = 0; i < root.iconOverrides.length; i++) {
      if (root.iconOverrides[i].process === name) return root.iconOverrides[i].icon
    }
    var bundled = root.bundledIcons[name]
    if (bundled) return "icons/" + bundled
    return root.iconUrlForName(name)
  }

  function normalizeIconOverrides(raw) {
    var out = []
    if (!raw || raw.length === undefined) return out
    for (var i = 0; i < raw.length; i++) {
      var e = raw[i] || {}
      var proc = String(e.process || "").toLowerCase().replace(/[^a-z0-9_-]/g, "")
      var icon = String(e.icon || "")
      if (!proc || !icon) continue
      out.push({ process: proc, icon: icon })
    }
    return out
  }

  Timer {
    id: probeTimer
    interval: 3000
    repeat: true
    running: root.probeNames().length > 0
    onTriggered: {
      root.probeOverrideWindows()
    }
  }

  // One reused process scans one window per run; results are attributed via
  // probeBusyPid rather than timing assumptions.
  Process {
    id: probeProcess
    stdout: StdioCollector {
      id: probeCollector
      waitForEnd: true
    }
    onExited: function() {
      if (root.probeBusyPid !== 0) {
        var matched = String(probeCollector.text || "").trim()
        root.probeCache[String(root.probeBusyPid)] = root.resolveProcessIcon(matched)
        root.probeTick++
      }
      root.probeBusyPid = 0
      root.pumpProbe()
    }
  }

  // icons/ is scanned rather than hard-coded so that dropping a PNG into the
  // directory is the entire workflow for adding an app. Rescanned on a slow
  // timer so a newly added file is picked up without restarting the shell.
  Process {
    id: iconScanProcess
    stdout: StdioCollector {
      id: iconScanCollector
      waitForEnd: true
    }
    onExited: function() {
      root.onIconsScanned(iconScanCollector.text)
    }
  }

  function scanBundledIcons() {
    if (iconScanProcess.running) return
    var dir = String(Qt.resolvedUrl("icons")).replace(/^file:\/\//, "")
    iconScanProcess.command = ["bash", "-c",
      "ls -1 '" + dir.replace(/'/g, "") + "' 2>/dev/null"]
    iconScanProcess.running = true
  }

  function onIconsScanned(text) {
    var map = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var file = lines[i].trim()
      if (!file) continue
      var dot = file.lastIndexOf(".")
      if (dot <= 0) continue
      var ext = file.substring(dot + 1).toLowerCase()
      if (ext !== "png" && ext !== "svg") continue
      var base = file.substring(0, dot).toLowerCase().replace(/[^a-z0-9_-]/g, "")
      if (base && !map[base]) map[base] = file
    }
    root.bundledIcons = map
    root.probeCache = ({})
    root.probeTick++
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.scanBundledIcons()
  }

  Process {
    id: clientFetchProcess
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      id: clientFetchCollector
      waitForEnd: true
    }
    onExited: function() {
      root.onClientsFetched(clientFetchCollector.text)
    }
  }

  function onClientsFetched(text) {
    var map = {}
    try {
      var arr = JSON.parse(text)
      for (var i = 0; i < arr.length; i++) {
        var c = arr[i]
        var size = c.size
        var area = size && size.length >= 2 ? Number(size[0]) * Number(size[1]) : 0
        map[String(c.address)] = {
          pid: Number(c.pid) || 0,
          area: area,
          klass: String(c.class || "")
        }
      }
    } catch (e) {
    }
    root.clientInfo = map
    root.pumpProbe()
  }

  function windowPid(tl) {
    if (!tl) return 0
    var info = root.clientInfo["0x" + tl.address]
    if (info && info.pid > 0) return info.pid
    try {
      var obj = tl.lastIpcObject
      if (obj && obj.pid) return Number(obj.pid)
    } catch (e) {
    }
    return 0
  }

  function windowOverrideIcon(tl) {
    var pid = root.windowPid(tl)
    return pid > 0 ? (root.probeCache[String(pid)] || "") : ""
  }

  function pumpProbe() {
    if (root.probeBusyPid !== 0 || root.probeQueue.length === 0) return
    root.probeBusyPid = root.probeQueue.shift()
    var names = root.probeNames()
    probeProcess.command = ["bash", "-c",
      "pstree -p " + root.probeBusyPid +
      " 2>/dev/null | grep -oE '(" + names.join("|") + ")\\(' | head -n1 | tr -d '('"]
    probeProcess.running = true
  }

  function probeOverrideWindows() {
    if (root.probeNames().length === 0) return
    var ids = root.workspaceIds()
    var seen = {}
    var want = []
    for (var i = 0; i < ids.length; i++) {
      var ws = root.workspaceById(ids[i])
      if (!ws) continue
      var tls = ws.toplevels.values
      var big = root.biggestWindowFor(tls)
      var pid = root.windowPid(big)
      if (pid <= 0 || seen[pid]) continue
      seen[pid] = true
      want.push(pid)
    }
    // Drop entries for windows that no longer exist. Never blank the cache:
    // slots keep their last known icon until a fresh probe completes, so
    // nothing flickers. Every current pid is re-probed so an override icon
    // also disappears when the app quits but the terminal stays open.
    var pruned = {}
    for (var key in root.probeCache) {
      var k = Number(key)
      if (seen[k]) pruned[key] = root.probeCache[key]
    }
    root.probeCache = pruned
    for (var j = 0; j < want.length; j++) {
      var p = want[j]
      if (p === root.probeBusyPid || root.probeQueue.indexOf(p) !== -1) continue
      root.probeQueue.push(p)
    }
    // Refresh the address -> pid/size map, then run the queued pstree scans.
    if (!clientFetchProcess.running) clientFetchProcess.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event) return
      var name = event.name
      if (name === "openwindow" || name === "closewindow" || name === "movewindow" ||
          name === "createworkspace" || name === "destroyworkspace") {
        root.bumpSync()
        root.probeOverrideWindows()
        return
      }
      if (name === "workspace" || name === "focusedworkspace" ||
          name === "activewindow" || name === "urgent") {
        root.bumpSync()
      }
    }
  }

  // Super-key reveal state. Hyprland routes SUPER press/release to the
  // "workspaceNumber" global shortcut (see ~/.config/hypr/bindings.lua).
  property bool superDown: false
  property bool superPressAndHeld: false

  GlobalShortcut {
    name: "workspaceNumber"
    description: "Hold to show workspace numbers, release to show icons"

    onPressed: {
      root.superDown = true
    }
    onReleased: {
      root.superDown = false
    }
  }

  Timer {
    id: superHoldTimer
    interval: root.revealDelay
    repeat: false
    onTriggered: {
      root.superPressAndHeld = true
    }
  }

  onSuperDownChanged: {
    if (root.superDown) {
      superHoldTimer.restart()
    } else {
      superHoldTimer.stop()
      root.superPressAndHeld = false
    }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // The window with the largest area on a workspace, mirroring the
  // illogical-impulse shell's biggestWindowForWorkspace(). Prefers the live
  // hyprctl client map (covers windows opened after the shell started).
  function biggestWindowFor(toplevels) {
    var best = null
    var bestArea = -1
    for (var i = 0; i < toplevels.length; i++) {
      var tl = toplevels[i]
      var area = 0
      var info = root.clientInfo["0x" + tl.address]
      if (info) {
        area = info.area
      } else {
        try {
          var size = tl.lastIpcObject ? tl.lastIpcObject.size : null
          if (size && size.length >= 2) area = Number(size[0]) * Number(size[1])
        } catch (e) {
        }
      }
      if (area > bestArea) {
        bestArea = area
        best = tl
      }
    }
    return best
  }

  function windowClass(tl) {
    if (!tl) return ""
    // Same staleness as pid/area: lastIpcObject is only filled during the
    // initial sync, so live hyprctl data wins for windows opened later.
    var info = root.clientInfo["0x" + tl.address]
    if (info && info.klass) return String(info.klass)
    try {
      var obj = tl.lastIpcObject
      if (obj && obj.class) return String(obj.class)
    } catch (e) {
    }
    try {
      var wayland = tl.wayland
      if (wayland && wayland.appId) return String(wayland.appId)
    } catch (e) {
    }
    return String(tl.title || "")
  }

  // Class -> icon path, mirroring AppSearch.guessIcon() fallback chain:
  // desktop entry lookup first, then the name as-is, lowercased, and the
  // last reverse-domain segment. Falls back to the generic executable icon.
  readonly property string genericIcon: Quickshell.iconPath("application-x-executable", true)

  // Icon name -> source URL. appLibrary is only injected into plugins whose
  // manifest declares the "menu" kind (see shell.qml's pluginShellFor), so a
  // bar-widget-only plugin always sees it as null and must resolve icons
  // itself. Returns "" when the name resolves to nothing.
  function iconUrlForName(name) {
    var value = String(name || "")
    if (!value) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    var lib = root.appLibrary
    if (lib) {
      // The library's index also covers icons installed after shell start.
      var viaLib = String(lib.iconSource(value) || "")
      return viaLib === root.genericIcon ? "" : viaLib
    }
    return Quickshell.iconPath(value, true)
  }

  // Window class -> desktop entry. byId() covers the common case where the
  // Hyprland class equals the desktop file id; the StartupWMClass sweep covers
  // the rest (class "zen" already matches zen.desktop, but e.g.
  // "code-url-handler" only resolves through StartupWMClass).
  function desktopEntryForClass(klass) {
    var value = String(klass || "")
    if (!value) return null

    var ids = [value]
    var lower = value.toLowerCase()
    if (lower !== value) ids.push(lower)
    var dot = value.lastIndexOf(".")
    if (dot >= 0 && dot < value.length - 1) {
      var segment = value.substring(dot + 1)
      ids.push(segment)
      var segmentLower = segment.toLowerCase()
      if (segmentLower !== segment) ids.push(segmentLower)
    }
    for (var i = 0; i < ids.length; i++) {
      try {
        var entry = DesktopEntries.byId(ids[i])
        if (entry) return entry
      } catch (e) {
      }
    }

    try {
      var values = DesktopEntries.applications.values
      for (var j = 0; j < values.length; j++) {
        var candidate = values[j]
        var wmClass = String(candidate.startupClass || "")
        if (wmClass && wmClass.toLowerCase() === lower) return candidate
      }
    } catch (e2) {
    }
    return null
  }

  // Class -> icon path, mirroring AppSearch.guessIcon() fallback chain:
  // desktop entry lookup first, then the name as-is, lowercased, and the
  // last reverse-domain segment. Falls back to the generic executable icon.
  function iconSourceForClass(klass) {
    klass = String(klass || "")

    var entry = root.desktopEntryForClass(klass)
    if (entry && entry.icon) {
      // The entry's Icon= key is the only thing that maps a class to an icon
      // whose name differs from it: zen -> zen-browser, and there is no icon
      // called "zen", so skipping this leaves the slot blank.
      var fromEntry = root.iconUrlForName(String(entry.icon))
      if (fromEntry) return fromEntry
    }

    var attempts = [klass]
    var lower = klass.toLowerCase()
    if (lower && lower !== klass) attempts.push(lower)
    var dot = klass.lastIndexOf(".")
    if (dot >= 0 && dot < klass.length - 1) {
      var segment = klass.substring(dot + 1)
      attempts.push(segment)
      var segmentLower = segment.toLowerCase()
      if (segmentLower !== segment) attempts.push(segmentLower)
    }

    for (var i = 0; i < attempts.length; i++) {
      var source = root.iconUrlForName(attempts[i])
      if (source) return source
    }
    return root.genericIcon
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // Slot geometry, used to position the animated active-workspace indicator.
  readonly property real slotWidth: root.vertical ? root.barSize : Style.space(20)
  readonly property real slotSpacing: root.vertical ? Style.space(2) : Style.space(1)
  readonly property real slotPitch: root.slotWidth + root.slotSpacing

  function focusedWorkspaceIndex() {
    var ws = Hyprland.focusedWorkspace
    if (!ws) return -1
    var ids = root.workspaceIds()
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] === ws.id) return i
    }
    return -1
  }

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  // Animated highlight that slides to the focused workspace slot while Super
  // is held, showing the switch target when navigating with SUPER + number.
  // Hidden by default; only appears once Super is pressed. Drawn behind slots.
  Rectangle {
    id: activeIndicator
    readonly property int focusIndex: root.focusedWorkspaceIndex()
    width: Math.round(Style.space(13))
    height: Math.round(Style.space(13))
    radius: Math.min(width, height) / 2
    color: Util.alpha(Color.accent, 0.55)
    visible: focusIndex >= 0
    opacity: root.superDown ? 1 : 0
    x: root.vertical
      ? (grid.width - width) / 2
      : focusIndex * root.slotPitch + (root.slotWidth - width) / 2
    y: root.vertical
      ? focusIndex * root.slotPitch + (root.slotWidth - height) / 2
      : (grid.height - height) / 2

    Behavior on opacity {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }
    Behavior on x {
      enabled: !root.vertical
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    Behavior on y {
      enabled: root.vertical
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: {
          // Reactive: re-evaluates on focus changes and on syncToken bumps so
          // occupancy/icon updates arrive even though the Hyprland collections
          // themselves are CONSTANT (non-notifying) QML properties. clientInfo
          // updates after each hyprctl fetch, re-running biggest-window logic.
          var _focus = Hyprland.focusedWorkspace
          var _sync = root.syncToken
          var _clients = root.clientInfo
          return root.workspaceById(modelData)
        }
        readonly property var toplevels: workspace ? workspace.toplevels.values : []
        readonly property var biggestWindow: root.biggestWindowFor(toplevels)
        readonly property bool occupied: toplevels.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        // Biggest window runs an overridden terminal app -> its custom icon.
        readonly property string overrideIcon: {
          var _tick = root.probeTick
          return root.windowOverrideIcon(biggestWindow)
        }
        // Occupied workspaces show their icon; empty/inactive ones show a
        // dimmed number. Holding Super swaps everything to numbers.
        readonly property bool showsIcon: root.showAppIcons && occupied && !root.superPressAndHeld

        bar: root.bar
        // Non-empty text keeps the slot visible; the built-in label is unused.
        text: modelData === 10 ? "0" : String(modelData)
        labelVisible: false
        dimmed: !occupied && !focused
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        // Biggest window's icon. Centered normally; while Super is held it
        // shrinks and floats to the slot's corner, mirroring the
        // illogical-impulse shell.
        Item {
          id: iconHost
          width: root.iconSize
          height: root.iconSize
          scale: root.superPressAndHeld ? 0.75 : 1.0
          opacity: parent.occupied && root.showAppIcons ? 1 : 0
          x: root.superPressAndHeld
            ? parent.width - width - Style.spaceReal(1)
            : (parent.width - width) / 2
          y: root.superPressAndHeld
            ? parent.height - height - Style.spaceReal(1)
            : (parent.height - height) / 2

          Behavior on x {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
          Behavior on y {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
          Behavior on scale {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }

          Image {
            id: wsIcon
            anchors.fill: parent
            visible: !root.monochromeIcons
            source: parent.parent.overrideIcon !== ""
              ? Qt.resolvedUrl(parent.parent.overrideIcon)
              : root.iconSourceForClass(root.windowClass(parent.parent.biggestWindow))
            fillMode: Image.PreserveAspectFit
            sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
            sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
            layer.enabled: root.monochromeIcons
            layer.smooth: true
          }

          MultiEffect {
            anchors.fill: parent
            source: wsIcon
            visible: root.monochromeIcons
            colorization: root.tintIcons ? 1.0 : 0.0
            colorizationColor: root.iconForeground
          }
        }

        // Workspace number. Always shown on empty/inactive workspaces; on
        // occupied ones it appears on top of the icon while Super is held.
        Text {
          anchors.centerIn: parent
          visible: !parent.showsIcon
          text: modelData === 10 ? "0" : String(modelData)
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
