pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "kit"
import "Model.js" as Model
import "GithubSummary.js" as GithubSummary
import "Preferences.js" as Schema
import "kit/FoamyPrefs.js" as Prefs

// The popup body: header, repository list (one keyboard/pointer cursor) and
// the settings page. Data comes from `service` (the Service singleton, or a
// mock in preview/Preview.qml); the Panel owns saving and the folder browser.
PanelKeyCatcher {
  id: root

  property QtObject service: null
  property var settings: ({})
  property bool opened: true
  property bool editingSettings: false
  property bool saving: false
  property string settingsError: ""
  property bool retryable: false
  property bool browsing: false
  // The stored list is invalid (the Panel says why): its editor is locked.
  property bool foldersLocked: false
  property bool trustLocked: false
  property double now: Date.now()
  property string searchText: ""
  property string filterMode: "all" // all, local, remote, cloned, notCloned
  property string sortMode: "updated" // updated, name, created
  property string section: "repos" // repos, pulls, issues

  signal closeRequestedByView
  signal settingsRequested
  signal settingsClosed
  signal saveRequested(string key, var value)
  signal foldersEdited(var rows)
  signal browseRequested(int index)
  signal retryRequested
  // Errors raised inside the view (clipboard paste) go to the Panel, which owns settingsError.
  signal settingsErrorReported(string message)
  signal switchPanelRequested(int direction)
  signal repositoryRequested(var repo)
  signal trustRequested(var repo, bool trusted)

  readonly property string query: String(searchText || "").trim().toLowerCase()
  function matchesQuery(text) {
    return query === "" || String(text || "").toLowerCase().indexOf(query) !== -1
  }
  // Clicking the active badge returns to repositories; the other two switch
  // the body to the bounded Pull requests / Issues page.
  function setSection(next) {
    var target = next === root.section ? "repos" : next
    if (target !== "repos" && target !== "pulls" && target !== "issues")
      return
    root.section = target
    cursor.reset()
  }
  readonly property bool showLocalSection: filterMode === "all" || filterMode === "local"
  readonly property bool showRemoteSection: filterMode === "all" || filterMode === "remote" || filterMode === "cloned" || filterMode === "notCloned"
  readonly property var repos: {
    var list = service ? service.affectedRepos : []
    if (!showLocalSection) return []
    if (query === "") return list
    return list.filter(function(repo) {
      return matchesQuery(repo.label) || matchesQuery(repo.path) || matchesQuery(Model.repositoryMeta(repo, FoamyI18n.t, FoamyI18n.tn))
    })
  }
  readonly property var displayRows: {
    var rows = []
    var local = root.repos
    for (var i = 0; i < local.length; i++)
      rows.push({ kind: "local", repo: local[i], localIndex: i })
    if (root.showLocalSection && local.length === 0)
      rows.push({ kind: "localEmpty" })
    if (root.showRemoteSection) {
      rows.push({ kind: "remoteHeader" })
      if (root.githubError !== "")
        rows.push({ kind: "remoteError" })
      if (!root.githubRefreshing && root.githubError === "" && root.githubRows.length === 0)
        rows.push({ kind: "remoteEmpty" })
      for (var j = 0; j < root.githubRows.length; j++)
        rows.push({ kind: "remote", row: root.githubRows[j] })
    }
    return rows
  }
  readonly property var totals: service ? service.totals : Model.defaultStatus().totals
  readonly property var sync: service ? service.sync : Model.defaultStatus().sync
  readonly property bool busy: !!service && service.busy
  readonly property bool hasFailures: sync.failures.length > 0
  function sortGithubRows(list) {
    var arr = (list || []).slice()
    arr.sort(function(a, b) {
      var ra = a.remote || {}, rb = b.remote || {}
      if (sortMode === "name")
        return String(ra.nameWithOwner || "").toLowerCase().localeCompare(String(rb.nameWithOwner || "").toLowerCase())
      var da = Date.parse(ra.pushedAt || ra.updatedAt || ra.createdAt || "") || 0
      var db = Date.parse(rb.pushedAt || rb.updatedAt || rb.createdAt || "") || 0
      if (sortMode === "created") {
        var ca = Date.parse(ra.createdAt || ra.pushedAt || "") || 0
        var cb = Date.parse(rb.createdAt || rb.pushedAt || "") || 0
        if (cb !== ca) return cb - ca
      } else if (db !== da) return db - da
      return String(ra.nameWithOwner || "").toLowerCase().localeCompare(String(rb.nameWithOwner || "").toLowerCase())
    })
    return arr
  }

  readonly property var githubRows: {
    var list = service ? service.githubRows : []
    if (!showRemoteSection) return []
    list = list.filter(function(row) {
      if (filterMode === "cloned") return !!row.local
      if (filterMode === "notCloned") return !row.local
      return true
    })
    if (query !== "") list = list.filter(function(row) {
      var r = row.remote || {}
      var local = row.local || {}
      return matchesQuery(r.nameWithOwner) || matchesQuery(r.description) || matchesQuery(r.url)
        || matchesQuery(local.label) || matchesQuery(local.path)
    })
    return sortGithubRows(list)
  }
  // Total loaded GitHub repositories for the bar header and badge, independent
  // of search/filter. The list heading still shows the visible row count, so
  // the two numbers answer different questions by design.
  readonly property int githubCount: {
    if (!service || service.githubEnabled === false)
      return 0
    var stats = Number((service.githubStats && service.githubStats.repoCount) || 0)
    return stats > 0 ? stats : (service.githubRows || []).length
  }
  readonly property string githubError: service ? (service.githubError || "") : ""
  readonly property bool githubRefreshing: !!service && service.githubRefreshing
  // Cursor stops: each row, then its "LFS" button when the repository uses
  // Git LFS and is untrusted, then (note open, trust available) its "Trust
  // this repository" button; then Settings (header) and Refresh (footer),
  // as in foamy-weather. Pull all sits before Settings, as in the header,
  // and only while something can be pulled (or a Pull all is running).
  readonly property var stops: {
    var rows = [], infos = [], trusts = [], count = 0
    for (var i = 0; i < repos.length; i++) {
      var lfs = !!repos[i] && repos[i].usesLfs === true && repos[i].trusted !== true && repos[i].complete !== false
      rows.push(count++)
      infos.push(lfs ? count++ : -1)
      trusts.push(lfs && repos[i].path === lfsNotePath && !!repos[i].identity ? count++ : -1)
    }
    return {
      rows: rows,
      infos: infos,
      trusts: trusts,
      count: count
    }
  }
  // The repository (path) whose Git LFS note is open under its row: one at a time.
  property string lfsNotePath: ""
  readonly property int pullableCount: service && service.pullableRepos ? service.pullableRepos.length : 0
  readonly property bool showPullAll: pullableCount > 0 || (!!service && service.pullingAll)
  readonly property int pullAllStop: showPullAll ? stops.count : -1
  readonly property int settingsStop: stops.count + (showPullAll ? 1 : 0)
  readonly property int refreshStop: settingsStop + 1
  readonly property var trustedList: Model.trustedRepositories(settings)
  readonly property var lfsRepositories: service && service.lfsRepos ? service.lfsRepos : []
  readonly property string healthText: {
    if (!service)
      return ""
    if (service.syncing)
      return FoamyI18n.t("Fetching repositories…")
    if (service.lastError !== "")
      return FoamyI18n.t("Repository check needs attention")
    if (service.lastChecked === 0)
      return FoamyI18n.t("Checking repositories…")
    if (service.status.repoCount === 0)
      return GithubSummary.emptyText(service.status.repoCount, root.githubCount, FoamyI18n.t)
    if (service.status.affectedCount === 0 && !sync.stale && !hasFailures)
      return FoamyI18n.t("Everything is in sync")
    if (service.status.affectedCount === 0 && !hasFailures)
      return FoamyI18n.t("Working trees are clean")
    return FoamyI18n.tn("%1 repositories need attention", Math.max(service.status.affectedCount, repos.length))
  }
  readonly property string statusTitle: service && service.actionStatus !== "" ? service.actionStatus : healthText
  readonly property bool animateTitle: !!service && (service.syncing || service.repositoryActionRunning || (service.refreshing && service.lastChecked === 0))
  property int progressStep: 0
  // Animated dots only while shown and motion is allowed; otherwise a static ellipsis.
  readonly property string displayTitle: animateTitle && !FoamyMotion.reduceMotion ? statusTitle.replace(/(?:…|\.{1,3})$/, "") + [".", "..", "..."][progressStep] : statusTitle
  readonly property string lastSyncText: FoamyI18n.t("Last remote sync %1", [Model.relativeTime(sync.lastSuccess, now, FoamyI18n.t)])

  implicitWidth: FoamyStyle.popupWidth
  implicitHeight: editingSettings ? settingsPage.implicitHeight : 560
  // While the search field or a dropdown owns keys, the panel cursor must
  // freeze; otherwise typing letters also triggers panel shortcuts and the
  // filter never feels live.
  blocked: editingSettings || (root.section === "repos" && (searchField.inputActiveFocus || filterSelect.triggerItem.activeFocus || sortSelect.triggerItem.activeFocus || filterSelect.popupOpen || sortSelect.popupOpen))

  // rows (+ LFS, trust), pull all, settings, refresh
  FoamyCursor {
    id: cursor
    count: root.refreshStop + 1
  }

  onMoveRequested: function (dx, dy) {
    if (root.section !== "repos") {
      // Left/h returns to repositories; right/l stays inert because the item
      // list has no second level. Vertical keys drive the item cursor.
      if (dx < 0)
        root.setSection("repos")
      else if (dy !== 0)
        itemsPage.move(dy)
      return
    }
    cursor.move(dy !== 0 ? dy : dx)
  }
  onActivateRequested: {
    if (root.section !== "repos")
      itemsPage.activate()
    else
      root.activate(cursor.index)
  }
  onCloseRequested: root.closeRequestedByView()
  onTabRequested: function (direction) {
    root.switchPanelRequested(direction)
  }
  onTextKey: function (text) {
    if (root.section !== "repos") {
      // Qt reports Backspace as U+0008 (and some platforms U+007F) through
      // PanelKeyCatcher's textKey.
      if (text === "\b" || text === "\u007f")
        root.setSection("repos")
      else if (text === "s" || text === "S")
        root.settingsRequested()
      return
    }
    if (text === "s" || text === "S")
      root.settingsRequested()
    else if ((text === "r" || text === "R") && !root.busy)
      root.service.fetch()
    else if (text === "p" || text === "P")
      root.pullAll()
  }
  onOpenedChanged: {
    if (opened) {
      // Type-to-filter should work as soon as the popup opens. Defer twice so
      // the host's own focus priming cannot put the cursor back on the panel.
      Qt.callLater(function () {
        Qt.callLater(root.section === "repos" ? searchField.focusInput : itemsPage.forceActiveFocus)
      })
    } else {
      cursor.reset()
      lfsNotePath = ""
      searchText = ""
      filterMode = "all"
      root.section = "repos"
    }
  }
  onSectionChanged: {
    cursor.reset()
    if (!root.opened)
      return
    Qt.callLater(function () {
      Qt.callLater(root.section === "repos" ? searchField.focusInput : itemsPage.forceActiveFocus)
    })
  }
  onSearchTextChanged: cursor.reset()
  onFilterModeChanged: cursor.reset()
  onEditingSettingsChanged: {
    if (editingSettings) {
      loadFolders()
      settingsPage.resetScroll()
      Qt.callLater(settingsPage.focusBack)
    } else {
      Qt.callLater(function () {
        if (root.section === "repos")
          searchField.focusInput()
        else
          itemsPage.forceActiveFocus()
      })
    }
  }

  Connections {
    target: cursor
    function onIndexChanged() {
      var row = root.rowForStop(cursor.index)
      if (row < 0) {
        if (cursor.index === root.settingsStop || cursor.index === root.pullAllStop) list.positionViewAtBeginning()
        else if (cursor.index === root.refreshStop) list.positionViewAtEnd()
        return
      }
      // find displayRows index for local row
      for (var i = 0; i < root.displayRows.length; i++) {
        var dr = root.displayRows[i]
        if (dr.kind === "local" && dr.localIndex === row) { list.positionViewAtIndex(i, ListView.Contain); return }
      }
    }
  }

  function rowForStop(index) {
    var row = stops.rows.indexOf(index)
    if (row < 0)
      row = stops.infos.indexOf(index)
    return row >= 0 ? row : stops.trusts.indexOf(index)
  }

  // Open or fold a repository's Git LFS note (the cursor stays where it is).
  function toggleLfsNote(repo) {
    if (!repo)
      return
    lfsNotePath = lfsNotePath === repo.path ? "" : String(repo.path)
  }

  // Preview/tests: open a row's Git LFS note with the cursor on its LFS button.
  function clearCursor() {
    cursor.reset()
    lfsNotePath = ""
  }
  function showLfsInfo(row) {
    if (row < 0 || row >= stops.infos.length || stops.infos[row] < 0)
      return
    lfsNotePath = String(repos[row].path)
    cursor.hover(stops.infos[row])
  }
  // Preview/tests: the keyboard cursor on the footer's Refresh button.
  function showRefreshCursor() {
    cursor.hover(refreshStop)
  }
  // Preview: scroll Settings to its end (the Git LFS section, when shown).
  function showSettingsEnd() {
    settingsPage.keepVisible(lfsSection.visible ? lfsSection : refreshSection)
  }

  function activate(index) {
    if (index < 0)
      return
    var info = stops.infos.indexOf(index)
    var trust = stops.trusts.indexOf(index)
    if (info >= 0)
      toggleLfsNote(repos[info])
    else if (trust >= 0) {
      root.trustRequested(repos[trust], true)
      lfsNotePath = ""
      // stay on that repository once its LFS button goes
      cursor.hover(stops.rows[trust])
    } else if (stops.rows.indexOf(index) >= 0)
      root.repositoryRequested(repos[stops.rows.indexOf(index)])
    else if (index === refreshStop) {
      if (!busy)
        service.fetch()
    } else if (index === settingsStop)
      root.settingsRequested()
    else if (index === pullAllStop)
      pullAll()
  }

  function pullAll() {
    if (service && !busy && pullableCount > 0)
      service.pullAll()
  }

  Timer {
    interval: 400
    repeat: true
    running: root.opened && root.animateTitle && !FoamyMotion.reduceMotion
    onRunningChanged: if (!running)
      root.progressStep = 0
    onTriggered: root.progressStep = (root.progressStep + 1) % 3
  }

  // "Updated N minutes ago" ages only while the popup is shown.
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  // ---- folder rows (settings) ---------------------------------------------------
  ListModel {
    id: folderRows
  }

  function loadFolders() {
    var result = Model.parseFolderRows(Model.repositoryFolders(root.settings))
    folderRows.clear()
    if (!result.error)
      result.folders.forEach(function (folder) {
        folderRows.append(folder)
      })
    if (folderRows.count === 0)
      folderRows.append({
        path: "",
        depth: 2
      })
  }

  function folderList() {
    var rows = []
    for (var i = 0; i < folderRows.count; i++) {
      var row = folderRows.get(i)
      // Blank editor rows are placeholders, not configured directories.
      if (row.path.trim() !== "")
        rows.push({
          path: row.path,
          depth: row.depth
        })
    }
    return rows
  }

  function setFolderPath(index, path) {
    if (index < 0 || index >= folderRows.count)
      return
    folderRows.setProperty(index, "path", path)
    root.foldersEdited(folderList())
    Qt.callLater(function () {
      var row = folderRepeater.itemAt(index)
      if (row)
        row.focusPath()
    })
  }

  function addFolder() {
    if (folderRows.count >= 32)
      return
    folderRows.append({
      path: "",
      depth: 2
    })
    Qt.callLater(function () {
      var row = folderRepeater.itemAt(folderRows.count - 1)
      if (row)
        row.focusPath()
    })
  }

  Column {
    id: mainColumn
    visible: !root.editingSettings
    anchors.fill: parent
    spacing: 0

    // Fixed top: hero, search, filters.
    Column {
      id: fixedHeader
      width: parent.width
      spacing: 0

      FoamyHeroBand {
        id: band
        width: parent.width
        iconName: "github"
        title: FoamyI18n.t("GitHub")
        meta: root.displayTitle
        settingsHasCursor: cursor.at(root.settingsStop)
        onSettingsClicked: root.settingsRequested()
        onSettingsHovered: function (hovered) {
          if (hovered)
            cursor.hover(root.settingsStop)
        }
        trailing: [
          FoamyAction {
            objectName: "refreshAction"
            iconName: "refresh-cw"
            spinning: !!root.service && (root.service.syncing || root.service.refreshing || root.service.githubRefreshing)
            tooltipText: root.busy ? FoamyI18n.t("Refreshing…") : FoamyI18n.t("Fetch remotes and refresh")
            actionEnabled: !root.busy
            hasCursor: cursor.at(root.refreshStop)
            foreground: FoamyPalette.secondaryText
            onHoveredChanged: if (hovered)
              cursor.hover(root.refreshStop)
            onClicked: root.activate(root.refreshStop)
          },
          FoamyAction {
            objectName: "pullAllAction"
            visible: root.showPullAll
            iconName: "arrow-down-to-line"
            tooltipText: (root.pullableCount > 0 ? FoamyI18n.tn("Pull %1 repositories", root.pullableCount) : FoamyI18n.t("Nothing to pull")) + " · P"
            actionEnabled: !root.busy && root.pullableCount > 0
            hasCursor: cursor.at(root.pullAllStop)
            foreground: FoamyPalette.secondaryText
            onHoveredChanged: if (hovered)
              cursor.hover(root.pullAllStop)
            onClicked: root.pullAll()
          }
        ]
        // Fixed cells keep the band a stable height while data refreshes;
        // a wrapping Flow made the header jump between one and three rows.
        Row {
          Layout.fillWidth: true
          spacing: FoamyStyle.gapSmall
          readonly property real cellWidth: (width - spacing * 3) / 4
          StatBadge { width: parent.cellWidth; alwaysVisible: true; icon: "box"; label: FoamyI18n.t("repos"); value: root.githubCount; tint: FoamyPalette.info }
          StatBadge { width: parent.cellWidth; alwaysVisible: true; icon: "git-branch"; label: FoamyI18n.t("open PRs"); value: root.service ? root.service.githubStats.openPRs : 0; tint: FoamyPalette.success; selectsSection: "pulls" }
          StatBadge { width: parent.cellWidth; alwaysVisible: true; icon: "circle-dot"; label: FoamyI18n.t("open issues"); value: root.service ? root.service.githubStats.openIssues : 0; tint: FoamyPalette.warning; selectsSection: "issues" }
          StatBadge { width: parent.cellWidth; alwaysVisible: true; icon: "activity"; label: FoamyI18n.t("commits"); value: root.service && root.service.githubActivity.weekly ? root.service.githubActivity.weekly.commits : 0; tint: FoamyPalette.accent }
        }

        // The contribution heatmap stays hidden: this popup is capped at 560px.
      }

      Item {
        id: bandSpacer
        width: parent.width
        height: FoamyStyle.gapLarge
        visible: root.section === "repos"
      }

      Column {
        id: filterColumn
        visible: root.section === "repos"
        x: FoamyStyle.padding
        width: parent.width - FoamyStyle.padding * 2
        spacing: FoamyStyle.gap

        Row {
          id: filterBar
          width: parent.width
          height: FoamyStyle.controlHeight
          spacing: FoamyStyle.gapSmall
          readonly property real captionWidth: FoamyStyle.unitWidth * 1.5
          readonly property real selectWidth: FoamyStyle.unitWidth * 3.25

          SafeTextField {
            id: searchField
            width: Math.max(0, parent.width - filterBar.captionWidth * 2 - filterBar.selectWidth * 2 - FoamyStyle.actionSize - parent.spacing * 5)
            height: FoamyStyle.controlHeight
            placeholderText: FoamyI18n.t("Search repositories…")
            text: root.searchText
            onTextEdited: root.searchText = text
            onKeyPressed: function (event) {
              // The panel key catcher is blocked while typing, so Escape must
              // be handled here or the popup cannot be closed from the field.
              if (event.key === Qt.Key_Escape) {
                event.accepted = true
                root.closeRequestedByView()
              }
            }
          }
          FoamyAction {
            id: clearSearch
            width: root.query !== "" ? FoamyStyle.actionSize : 0
            height: FoamyStyle.actionSize
            anchors.verticalCenter: parent.verticalCenter
            visible: root.query !== ""
            iconName: "x"
            tooltipText: FoamyI18n.t("Clear search")
            foreground: FoamyPalette.secondaryText
            onClicked: {
              root.searchText = ""
              searchField.text = ""
              searchField.focusInput()
            }
          }
          Text {
            id: filterLabel
            width: filterBar.captionWidth
            anchors.verticalCenter: parent.verticalCenter
            text: FoamyI18n.t("Filter")
            textFormat: Text.PlainText
            color: FoamyPalette.secondaryText
            font.family: FoamyStyle.fontFamily
            font.pixelSize: FoamyStyle.font.caption
          }
          FoamyDropdown {
            id: filterSelect
            width: filterBar.selectWidth
            height: FoamyStyle.controlHeight
            showLabel: false
            foreground: FoamyPalette.text
            value: root.filterMode
            options: [
              { value: "all", label: FoamyI18n.t("All") },
              { value: "local", label: FoamyI18n.t("Local") },
              { value: "remote", label: FoamyI18n.t("Remote") },
              { value: "cloned", label: FoamyI18n.t("Cloned") },
              { value: "notCloned", label: FoamyI18n.t("Not cloned") }
            ]
            Accessible.name: filterLabel.text
            onChanged: function (value) { root.filterMode = value }
          }
          Text {
            id: sortLabel
            width: filterBar.captionWidth
            anchors.verticalCenter: parent.verticalCenter
            text: FoamyI18n.t("Sort")
            textFormat: Text.PlainText
            color: FoamyPalette.secondaryText
            font.family: FoamyStyle.fontFamily
            font.pixelSize: FoamyStyle.font.caption
          }
          FoamyDropdown {
            id: sortSelect
            width: filterBar.selectWidth
            height: FoamyStyle.controlHeight
            showLabel: false
            foreground: FoamyPalette.text
            value: root.sortMode
            options: [
              { value: "updated", label: FoamyI18n.t("Updated") },
              { value: "name", label: FoamyI18n.t("Name") },
              { value: "created", label: FoamyI18n.t("Created") }
            ]
            Accessible.name: sortLabel.text
            onChanged: function (value) { root.sortMode = value }
          }
        }

        // Local status stays outside the filter row: it appears only when a
        // repository actually has something to report.
        Flow {
          width: parent.width
          visible: root.totals.aheadRepos > 0 || root.totals.behindRepos > 0 || root.totals.dirtyRepos > 0
          spacing: FoamyStyle.gapSmall
          StatBadge { icon: "arrow-up"; label: FoamyI18n.t("ahead"); value: root.totals.aheadRepos; tint: FoamyPalette.onSurface(FoamyPalette.success) }
          StatBadge { icon: "arrow-down"; label: FoamyI18n.t("behind"); value: root.totals.behindRepos; tint: FoamyPalette.onSurface(FoamyPalette.info) }
          StatBadge { icon: "pencil"; label: FoamyI18n.t("changed"); value: root.totals.dirtyRepos; tint: FoamyPalette.onSurface(FoamyPalette.warning) }
        }
      }

      Item {
        id: filterSpacer
        width: parent.width
        height: FoamyStyle.gap
        visible: root.section === "repos"
      }

      Text {
        id: statusWarning
        visible: root.section === "repos" && !!root.service && (root.service.lastError !== "" || root.sync.stale)
        x: FoamyStyle.padding
        width: parent.width - FoamyStyle.padding * 2
        bottomPadding: FoamyStyle.gap
        text: !root.service ? "" : root.service.lastError !== "" ? FoamyI18n.t(root.service.lastError) : root.lastSyncText + " · " + FoamyI18n.t("remote state may be stale")
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignLeft
        color: root.service && root.service.lastError !== "" ? FoamyPalette.onSurface(FoamyPalette.error) : FoamyPalette.onSurface(FoamyPalette.warning)
        font.family: FoamyStyle.fontFamily
        font.pixelSize: FoamyStyle.font.bodySmall
        Accessible.role: root.service && root.service.lastError !== "" ? Accessible.AlertMessage : Accessible.StaticText
      }
    }

    ListView {
      id: list
      visible: root.section === "repos"
      width: parent.width
      height: Math.max(0, mainColumn.height - fixedHeader.height)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      model: root.editingSettings ? [] : root.displayRows
      cacheBuffer: 0
      reuseItems: true
      FoamyWheelScroll {
        id: wheel
        target: list
      }
      ScrollBar.vertical: ScrollBar {
        id: vbar
        visible: list.interactive
        policy: ScrollBar.AsNeeded
        width: FoamyStyle.gap
        padding: 1
        contentItem: Rectangle {
          implicitWidth: FoamyStyle.gap - 2
          radius: FoamyStyle.pillRadius(width)
          color: vbar.pressed ? FoamyPalette.accent : vbar.hovered ? FoamyPalette.text : FoamyPalette.secondaryText
          opacity: vbar.active ? 0.9 : 0.45
        }
        background: Rectangle {
          radius: FoamyStyle.pillRadius(width)
          color: Qt.alpha(FoamyPalette.text, 0.06)
        }
      }
      delegate: Loader {
        id: rowLoader
        required property var modelData
        required property int index
        width: list.width
        sourceComponent: {
          var k = modelData ? modelData.kind : ""
          if (k === "local") return localRowComp
          if (k === "localEmpty") return localEmptyComp
          if (k === "remoteHeader") return remoteHeaderComp
          if (k === "remoteError") return remoteErrorComp
          if (k === "remoteEmpty") return remoteEmptyComp
          if (k === "remote") return remoteRowComp
          return null
        }
        // Inline components cannot see the delegate's id; hand them the row.
        Binding {
          when: rowLoader.item !== null
          target: rowLoader.item
          property: "rowData"
          value: rowLoader.modelData
        }
      }

      Component {
        id: localRowComp
        Item {
          property var rowData: null
          width: list.width
          height: surface.height + FoamyStyle.gapTiny
          RepositoryRow {
            id: surface
            x: FoamyStyle.gapLarge
            width: parent.width - FoamyStyle.gapLarge * 2
            repo: rowData ? rowData.repo : null
            rowIndex: rowData ? rowData.localIndex : -1
          }
        }
      }
      Component {
        id: localEmptyComp
        StateNote {
          rowData: null
          message: !root.service ? "" : root.query !== "" ? FoamyI18n.t("No local repositories match your search.") : root.service.lastError !== "" ? FoamyI18n.t("Local repository status is unavailable. Try Refresh again.") : root.service.lastChecked === 0 ? FoamyI18n.t("Checking local repositories…") : root.service.status.repoCount === 0 ? FoamyI18n.t("No local repositories found. Add a folder in Settings or clone from GitHub below.") : FoamyI18n.t("All local repositories are clean and match their upstream")
        }
      }
      Component {
        id: remoteErrorComp
        StateNote {
          rowData: null
          error: true
          message: root.githubError
        }
      }
      Component {
        id: remoteEmptyComp
        StateNote {
          rowData: null
          message: root.query !== "" ? FoamyI18n.t("No GitHub repositories match your search.") : FoamyI18n.t("No GitHub repositories loaded. Check gh auth status or refresh.")
        }
      }
      Component {
        id: remoteHeaderComp
        Item {
          property var rowData: null
          width: list.width - FoamyStyle.padding * 2
          x: FoamyStyle.padding
          height: FoamyStyle.gapLarge + heading.implicitHeight + FoamyStyle.gap
          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: FoamyStyle.gapLarge
            spacing: FoamyStyle.gapSmall
            Text {
              id: heading
              anchors.verticalCenter: parent.verticalCenter
              text: FoamyI18n.t("GitHub repositories")
              textFormat: Text.PlainText
              color: FoamyPalette.text
              font.family: FoamyStyle.fontFamily
              font.pixelSize: FoamyStyle.font.title
              font.weight: Font.DemiBold
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.githubRefreshing && root.githubRows.length > 0
              text: FoamyI18n.number(root.githubRows.length)
              textFormat: Text.PlainText
              color: FoamyPalette.mutedText
              font.family: FoamyStyle.monoFamily
              font.pixelSize: FoamyStyle.font.bodySmall
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.githubRefreshing
              text: FoamyI18n.t("Loading…")
              textFormat: Text.PlainText
              color: FoamyPalette.secondaryText
              font.family: FoamyStyle.fontFamily
              font.pixelSize: FoamyStyle.font.caption
            }
          }
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: FoamyPalette.divider
          }
        }
      }
      Component {
        id: remoteRowComp
        Item {
          property var rowData: null
          width: list.width
          height: remoteRow.height
          GithubRemoteRow {
            id: remoteRow
            width: parent.width
            row: rowData ? rowData.row : null
          }
        }
      }
    }

    GithubItemsView {
      id: itemsPage
      visible: root.section !== "repos"
      width: parent.width
      height: Math.max(0, mainColumn.height - fixedHeader.height)
      section: root.section
      onBackRequested: root.setSection("repos")
    }
  }

  // ---- settings -------------------------------------------------------------------
  FoamySettingsPage {
    id: settingsPage
    visible: root.editingSettings
    width: parent.width
    height: parent.height
    saving: root.saving
    error: root.settingsError
    retryable: root.retryable
    onBack: root.settingsClosed()
    onRetry: root.retryRequested()

    FoamySettingsSection {
      width: parent.width
      title: FoamyI18n.t("GitHub")
      description: FoamyI18n.t("Browse your GitHub repositories with gh and clone them locally.")

      FoamyToggle {
        width: parent.width
        label: FoamyI18n.t("Show GitHub repositories")
        checked: !!root.settings.githubEnabled
        onClicked: root.saveRequested("githubEnabled", !checked)
      }
      FoamyTextSettingField {
        width: parent.width
        label: FoamyI18n.t("Clone directory")
        value: String(root.settings.cloneDirectory || "~/repos")
        placeholderText: "~/repos"
        onCommitted: function(value) { root.saveRequested("cloneDirectory", value) }
      }
      FoamyNumberField {
        width: parent.width
        label: FoamyI18n.t("Refresh GitHub repositories every (minutes)")
        value: Number(root.settings.githubRefreshMinutes || 5)
        from: 1
        to: 120
        stepSize: 1
        onCommitted: function(value) { root.saveRequested("githubRefreshMinutes", value) }
      }
      FoamyNumberField {
        width: parent.width
        label: FoamyI18n.t("GitHub repositories to load")
        value: Number(root.settings.githubLimit || 100)
        from: 1
        to: 200
        stepSize: 1
        onCommitted: function(value) { root.saveRequested("githubLimit", value) }
      }
    }

    FoamySettingsSection {
      width: parent.width
      title: FoamyI18n.t("Repository folders")
      description: FoamyI18n.t("Folders to search for Git repositories, and how many levels deep.")

      Repeater {
        id: folderRepeater
        model: folderRows
        Column {
          id: folderRow
          required property int index
          required property string path
          required property int depth
          function focusPath() {
            folderPath.forceActiveFocus()
          }
          width: parent.width
          spacing: FoamyStyle.gapTiny
          enabled: !root.browsing && !root.foldersLocked

          Text {
            width: parent.width
            text: FoamyI18n.t("Repository folder %1", [folderRow.index + 1])
            textFormat: Text.PlainText
            color: FoamyPalette.secondaryText
            font.family: FoamyStyle.fontFamily
            font.pixelSize: FoamyStyle.font.bodySmall
          }
          Row {
            width: parent.width
            height: FoamyStyle.controlHeight
            spacing: FoamyStyle.gapSmall

            FoamyAction {
              width: FoamyStyle.actionSize
              height: FoamyStyle.actionSize
              anchors.verticalCenter: parent.verticalCenter
              iconName: "folder"
              focusable: true
              tooltipText: FoamyI18n.t("Browse for folder")
              foreground: FoamyPalette.secondaryText
              onClicked: root.browseRequested(folderRow.index)
            }
            SafeTextField {
              id: folderPath
              width: Math.max(0, parent.width - FoamyStyle.actionSize * 2 - FoamyStyle.unitWidth * 3 - parent.spacing * 3)
              implicitHeight: FoamyStyle.controlHeight
              anchors.verticalCenter: parent.verticalCenter
              text: folderRow.path
              placeholderText: "~/Projects"
              translate: FoamyI18n.t
              Accessible.name: FoamyI18n.t("Repository folder %1", [folderRow.index + 1])
              onPasteErrorChanged: if (pasteError !== "")
                root.settingsErrorReported(pasteError)
              onTextEdited: folderRows.setProperty(folderRow.index, "path", text)
              onEditingFinished: root.foldersEdited(root.folderList())
              onInputActiveFocusChanged: if (inputActiveFocus)
                settingsPage.keepVisible(folderRow)
            }
            FoamyDropdown {
              width: FoamyStyle.unitWidth * 3
              height: FoamyStyle.controlHeight
              anchors.verticalCenter: parent.verticalCenter
              showLabel: false
              label: FoamyI18n.t("Scan levels for %1", [folderRow.path])
              value: String(folderRow.depth)
              options: [0, 1, 2, 3, 4, 5].map(function (depth) {
                return {
                  value: String(depth),
                  label: FoamyI18n.tn("%1 levels", depth)
                }
              })
              onChanged: function (value) {
                folderRows.setProperty(folderRow.index, "depth", Number(value))
                root.foldersEdited(root.folderList())
              }
            }
            FoamyAction {
              width: FoamyStyle.actionSize
              height: FoamyStyle.actionSize
              anchors.verticalCenter: parent.verticalCenter
              iconName: "trash"
              focusable: true
              destructive: true
              tooltipText: FoamyI18n.t("Remove folder")
              foreground: FoamyPalette.secondaryText
              onClicked: {
                folderRows.remove(folderRow.index)
                if (folderRows.count === 0)
                  folderRows.append({
                    path: "",
                    depth: 2
                  })
                root.foldersEdited(root.folderList())
              }
            }
          }
        }
      }
      FoamyButton {
        iconName: "plus"
        text: FoamyI18n.t("Add folder")
        focusable: true
        tooltipText: folderRows.count >= 32 ? FoamyI18n.t("You can add up to 32 folders.") : ""
        actionEnabled: folderRows.count < 32 && !root.browsing && !root.foldersLocked
        onClicked: root.addFolder()
      }
    }

    FoamySettingsSection {
      id: refreshSection
      width: parent.width
      title: FoamyI18n.t("Refresh")
      FoamyToggle {
        width: parent.width
        label: FoamyI18n.t("Detect changes automatically")
        description: FoamyI18n.t("Recommended. Watches the repositories for changes.")
        checked: Prefs.value(Schema.fields, root.settings, "inotifyEnabled")
        onClicked: root.saveRequested("inotifyEnabled", !checked)
      }
      FoamyDropdown {
        width: parent.width
        compact: true
        label: Prefs.value(Schema.fields, root.settings, "inotifyEnabled") ? FoamyI18n.t("Fallback refresh every") : FoamyI18n.t("Refresh every")
        value: String(Prefs.value(Schema.fields, root.settings, "refreshIntervalSec"))
        options: [
          {
            value: "0",
            label: FoamyI18n.t("Off")
          },
          {
            value: "10",
            label: FoamyI18n.tn("%1 seconds", 10)
          },
          {
            value: "30",
            label: FoamyI18n.tn("%1 seconds", 30)
          },
          {
            value: "60",
            label: FoamyI18n.tn("%1 minutes", 1)
          },
          {
            value: "300",
            label: FoamyI18n.tn("%1 minutes", 5)
          }
        ]
        onChanged: function (value) {
          root.saveRequested("refreshIntervalSec", Number(value))
        }
      }
      FoamyDropdown {
        width: parent.width
        compact: true
        label: FoamyI18n.t("Fetch remotes every")
        value: String(Prefs.value(Schema.fields, root.settings, "fetchIntervalSec"))
        options: [
          {
            value: "300",
            label: FoamyI18n.tn("%1 minutes", 5)
          },
          {
            value: "900",
            label: FoamyI18n.tn("%1 minutes", 15)
          },
          {
            value: "1800",
            label: FoamyI18n.tn("%1 minutes", 30)
          },
          {
            value: "3600",
            label: FoamyI18n.tn("%1 hours", 1)
          }
        ]
        onChanged: function (value) {
          root.saveRequested("fetchIntervalSec", Number(value))
        }
      }
    }

    // Git LFS: per-repository trust, only when a repository using LFS was found.
    // The long explanation is the section's (i) note, not a tooltip.
    FoamySettingsSection {
      id: lfsSection
      width: parent.width
      visible: root.lfsRepositories.length > 0
      title: FoamyI18n.t("Git LFS")
      description: FoamyI18n.t("Turn on for repositories you trust. They then run their own Git LFS settings during automatic checks.")
      info: FoamyI18n.t("Automatic checks run Git without a repository's own settings, filters and hooks, so nothing in a repository can run code just by being in these folders. For Git LFS that means files you edited may show as changed until Git refreshes. A trusted repository runs its own Git settings, including LFS, during automatic checks and fetches, so its counts are exact. Trust applies to the repository at that exact path; moving or renaming it removes the trust.")
      Repeater {
        model: root.lfsRepositories
        FoamyToggle {
          required property var modelData
          width: lfsSection.width
          label: String(modelData.label)
          description: modelData.identity ? String(modelData.path) : FoamyI18n.t("Trust isn't available for this repository's filesystem.")
          enabled: !!modelData.identity && !root.trustLocked
          checked: Model.isTrusted(root.trustedList, modelData)
          onClicked: root.trustRequested(modelData, !checked)
        }
      }
    }
  }

  // ---- components ---------------------------------------------------------------------
  component StateNote: Rectangle {
    id: stateNote
    property var rowData: null
    property string message: ""
    property bool error: false
    x: FoamyStyle.padding
    width: list.width - FoamyStyle.padding * 2
    height: noteText.implicitHeight + FoamyStyle.gapLarge * 2
    radius: FoamyStyle.radiusSmall
    color: FoamyPalette.noteFill
    Rectangle {
      width: 2
      height: parent.height - FoamyStyle.gapLarge * 2
      anchors.left: parent.left
      anchors.leftMargin: FoamyStyle.gap
      anchors.verticalCenter: parent.verticalCenter
      radius: FoamyStyle.pillRadius(width)
      visible: stateNote.error
      color: FoamyPalette.onSurface(FoamyPalette.error)
    }
    Text {
      id: noteText
      x: FoamyStyle.gapLarge
      y: FoamyStyle.gapLarge
      width: parent.width - FoamyStyle.gapLarge * 2
      text: message
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: stateNote.error ? FoamyPalette.onSurface(FoamyPalette.error) : FoamyPalette.secondaryText
      font.family: FoamyStyle.fontFamily
      font.pixelSize: FoamyStyle.font.bodySmall
    }
  }

  component StatBadge: Rectangle {
    id: badge
    property string icon: ""
    property string label: ""
    property int value: 0
    property color tint: FoamyPalette.text
    property bool alwaysVisible: false
    property string selectsSection: ""
    objectName: badge.selectsSection ? badge.selectsSection + "Badge" : ""
    visible: alwaysVisible || value > 0
    radius: FoamyStyle.radiusSmall
    color: Qt.alpha(tint, 0.12)
    border.width: 1
    border.color: Qt.alpha(tint, 0.22)
    implicitHeight: badgeRow.implicitHeight + FoamyStyle.gapSmall * 2
    implicitWidth: badgeRow.implicitWidth + FoamyStyle.gap * 2
    Row {
      id: badgeRow
      anchors.centerIn: parent
      spacing: FoamyStyle.gapSmall
      FoamyIcon { name: icon; width: FoamyStyle.font.bodySmall; height: FoamyStyle.font.bodySmall; color: tint; anchors.verticalCenter: parent.verticalCenter }
      Text { text: FoamyI18n.number(value); textFormat: Text.PlainText; color: tint; font.family: FoamyStyle.fontFamily; font.pixelSize: FoamyStyle.font.bodySmall; font.weight: Font.DemiBold }
      Text { text: label; textFormat: Text.PlainText; color: FoamyPalette.secondaryText; font.family: FoamyStyle.fontFamily; font.pixelSize: FoamyStyle.font.caption }
    }
    MouseArea {
      anchors.fill: parent
      enabled: badge.selectsSection !== ""
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.setSection(badge.selectsSection)
    }
  }

  component ContributionGraph: Column {
    property var graph: null
    spacing: FoamyStyle.gapSmall
    readonly property var weeks: graph && graph.weeks ? graph.weeks : []
    readonly property int total: graph ? Number(graph.total || 0) : 0

    RowLayout {
      width: parent.width
      spacing: FoamyStyle.gapSmall
      Text {
        Layout.fillWidth: true
        text: FoamyI18n.t("%1 contributions in the last year", [FoamyI18n.number(parent.parent.total)])
        textFormat: Text.PlainText
        color: FoamyPalette.secondaryText
        font.family: FoamyStyle.fontFamily
        font.pixelSize: FoamyStyle.font.caption
      }
      Row {
        spacing: 3
        Text { text: FoamyI18n.t("Less"); color: FoamyPalette.mutedText; font.family: FoamyStyle.fontFamily; font.pixelSize: FoamyStyle.font.caption; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
          model: [0,1,2,3,4]
          Rectangle {
            required property int modelData
            width: 8; height: 8; radius: 2
            color: modelData === 0 ? Qt.alpha(FoamyPalette.text, 0.08)
                 : modelData === 1 ? Qt.alpha(FoamyPalette.success, 0.28)
                 : modelData === 2 ? Qt.alpha(FoamyPalette.success, 0.48)
                 : modelData === 3 ? Qt.alpha(FoamyPalette.success, 0.72)
                 : FoamyPalette.success
          }
        }
        Text { text: FoamyI18n.t("More"); color: FoamyPalette.mutedText; font.family: FoamyStyle.fontFamily; font.pixelSize: FoamyStyle.font.caption; anchors.verticalCenter: parent.verticalCenter }
      }
    }

    Flickable {
      width: parent.width
      height: heatGrid.implicitHeight
      contentWidth: heatGrid.implicitWidth
      clip: true
      interactive: contentWidth > width
      boundsBehavior: Flickable.StopAtBounds
      Row {
        id: heatGrid
        spacing: 2
        Repeater {
          model: weeks
          delegate: Column {
            required property var modelData
            spacing: 2
            Repeater {
              model: modelData
              delegate: Rectangle {
                required property var modelData
                width: 8; height: 8; radius: 2
                color: {
                  var l = Number(modelData.level || 0)
                  return l <= 0 ? Qt.alpha(FoamyPalette.text, 0.08)
                       : l === 1 ? Qt.alpha(FoamyPalette.success, 0.28)
                       : l === 2 ? Qt.alpha(FoamyPalette.success, 0.48)
                       : l === 3 ? Qt.alpha(FoamyPalette.success, 0.72)
                       : FoamyPalette.success
                }

              }
            }
          }
        }
      }
    }
  }


  component GithubRemoteRow: FoamyCursorSurface {
    id: remoteRow
    property var row: null
    readonly property var remote: row ? row.remote : null
    readonly property var local: row ? row.local : null
    readonly property bool cloned: !!local
    readonly property string meta: {
      if (!remote) return ""
      var bits = []
      bits.push(remote.isPrivate ? FoamyI18n.t("Private") : FoamyI18n.t("Public"))
      if (remote.isFork) bits.push(FoamyI18n.t("Fork"))
      if (remote.isArchived) bits.push(FoamyI18n.t("Archived"))
      if (remote.pushedAt) bits.push(FoamyI18n.t("Pushed %1", [Model.relativeTime(Date.parse(remote.pushedAt) / 1000, root.now, FoamyI18n.t)]))
      if (cloned && local.complete !== false) bits.push(Model.repositoryMeta(local, FoamyI18n.t, FoamyI18n.tn))
      else if (cloned) bits.push(FoamyI18n.t("Local status unavailable"))
      else bits.push(FoamyI18n.t("Not cloned"))
      return bits.join(" · ")
    }
    // Plain Rows/Columns: a RowLayout here polishes in a loop when GitHub data
    // refreshes, which freezes the shell.
    height: FoamyStyle.rowPadding * 2 + Math.max(FoamyStyle.controlHeight,
      titleText.implicitHeight + (descText.visible ? descText.implicitHeight + FoamyStyle.gapTiny : 0)
      + FoamyStyle.gapTiny + metaText.implicitHeight)
    hasCursor: false

    Row {
      id: remoteContent
      x: FoamyStyle.rowPadding
      y: FoamyStyle.rowPadding
      width: parent.width - FoamyStyle.rowPadding - FoamyStyle.gapSmall
      height: parent.height - FoamyStyle.rowPadding * 2
      spacing: FoamyStyle.rowPadding

      Rectangle {
        id: stateBar
        width: 2
        height: FoamyStyle.controlHeight
        anchors.verticalCenter: parent.verticalCenter
        radius: FoamyStyle.pillRadius(width)
        color: !remote ? FoamyPalette.secondaryText : cloned ? (local && local.dirtyCount > 0 ? FoamyPalette.warning : FoamyPalette.success) : FoamyPalette.info
      }

      Column {
        id: details
        width: Math.max(0, parent.width - stateBar.width - actions.width - parent.spacing * 2)
        anchors.verticalCenter: parent.verticalCenter
        spacing: FoamyStyle.gapTiny
        Row {
          width: parent.width
          height: titleText.implicitHeight
          Text {
            id: titleText
            width: Math.max(0, parent.width - (privateIcon.visible ? privateIcon.width : 0)
              - (forkIcon.visible ? forkIcon.width : 0) - (archiveIcon.visible ? archiveIcon.width : 0)
              - (privateIcon.visible ? parent.spacing : 0) - (forkIcon.visible ? parent.spacing : 0)
              - (archiveIcon.visible ? parent.spacing : 0))
            anchors.verticalCenter: parent.verticalCenter
            text: remote ? String(remote.nameWithOwner) : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: FoamyPalette.text
            font.family: FoamyStyle.fontFamily
            font.pixelSize: FoamyStyle.font.title
            font.weight: Font.DemiBold
          }
          FoamyIcon {
            id: privateIcon
            visible: !!remote && remote.isPrivate
            name: "lock"
            width: FoamyStyle.font.bodySmall; height: FoamyStyle.font.bodySmall
            color: FoamyPalette.info
            anchors.verticalCenter: parent.verticalCenter
          }
          FoamyIcon {
            id: forkIcon
            visible: !!remote && remote.isFork
            name: "git-fork"
            width: FoamyStyle.font.bodySmall; height: FoamyStyle.font.bodySmall
            color: FoamyPalette.secondaryText
            anchors.verticalCenter: parent.verticalCenter
          }
          FoamyIcon {
            id: archiveIcon
            visible: !!remote && remote.isArchived
            name: "archive"
            width: FoamyStyle.font.bodySmall; height: FoamyStyle.font.bodySmall
            color: FoamyPalette.mutedText
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        Text {
          id: descText
          visible: !!remote && String(remote.description || "") !== ""
          width: parent.width
          text: remote ? String(remote.description || "") : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          maximumLineCount: 1
          color: FoamyPalette.secondaryText
          font.family: FoamyStyle.fontFamily
          font.pixelSize: FoamyStyle.font.bodySmall
        }
        Row {
          width: parent.width
          height: Math.max(metaIcon.height, metaText.implicitHeight)
          FoamyIcon {
            id: metaIcon
            name: remoteRow.cloned ? "check" : "download"
            width: FoamyStyle.font.bodySmall; height: FoamyStyle.font.bodySmall
            color: remoteRow.cloned ? FoamyPalette.success : FoamyPalette.secondaryText
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            id: metaText
            width: Math.max(0, parent.width - metaIcon.width - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            text: remoteRow.meta
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: FoamyPalette.secondaryText
            font.family: FoamyStyle.fontFamily
            font.pixelSize: FoamyStyle.font.bodySmall
          }
        }
      }

      Row {
        id: actions
        spacing: FoamyStyle.gapSmall
        anchors.verticalCenter: parent.verticalCenter
        FoamyAction {
          iconName: "external-link"
          tooltipText: FoamyI18n.t("Open on GitHub")
          enabled: !!remote
          foreground: FoamyPalette.secondaryText
          onClicked: if (root.service) root.service.openGithubUrl(remote)
        }
        FoamyAction {
          visible: !remoteRow.cloned
          iconName: "download"
          tooltipText: FoamyI18n.t("Clone repository")
          enabled: !!remote && !!root.service && !root.service.repositoryActionRunning
          foreground: FoamyPalette.secondaryText
          onClicked: if (root.service) root.service.cloneGithubRepo(remote)
        }
        FoamyAction {
          visible: remoteRow.cloned
          iconName: "arrow-down"
          tooltipText: FoamyI18n.t("Pull %1", [remote ? String(remote.nameWithOwner) : ""])
          enabled: !!root.service && Model.canPull(local)
          foreground: FoamyPalette.secondaryText
          onClicked: if (root.service && local) root.service.pullRepository(local)
        }
        FoamyAction {
          visible: remoteRow.cloned
          iconName: "refresh-cw"
          tooltipText: FoamyI18n.t("Fetch %1", [remote ? String(remote.nameWithOwner) : ""])
          enabled: !!root.service && !root.busy
          foreground: FoamyPalette.secondaryText
          onClicked: if (root.service) root.service.fetch()
        }
        FoamyAction {
          visible: remoteRow.cloned
          iconName: "eye"
          tooltipText: FoamyI18n.t("Open in lazygit")
          enabled: !!remoteRow.cloned
          foreground: FoamyPalette.secondaryText
          onClicked: if (root.service) root.service.openGithubLocal(row)
        }
      }
    }
  }
  component RepositoryRow: FoamyCursorSurface {
    id: repoRow
    property var repo: null
    property int rowIndex: 0
    readonly property bool unavailable: !!repo && repo.complete === false
    readonly property string meta: Model.repositoryMeta(repo, FoamyI18n.t, FoamyI18n.tn)
    readonly property string syncError: Model.syncErrorText(repo, FoamyI18n.t)
    readonly property color stateColor: !repo ? FoamyPalette.success : repo.complete === false || repo.syncError ? FoamyPalette.error : repo.dirtyCount > 0 ? FoamyPalette.warning : repo.behind > 0 ? FoamyPalette.info : FoamyPalette.success

    height: content.implicitHeight + FoamyStyle.rowPadding * 2 + (lfsPanel.visible ? lfsPanel.implicitHeight + FoamyStyle.gap : 0)
    readonly property int rowStop: root.stops.rows[rowIndex] !== undefined ? root.stops.rows[rowIndex] : -1
    readonly property int infoStop: root.stops.infos[rowIndex] !== undefined ? root.stops.infos[rowIndex] : -1
    readonly property int trustStop: root.stops.trusts[rowIndex] !== undefined ? root.stops.trusts[rowIndex] : -1
    readonly property bool lfs: !!repo && repo.usesLfs === true
    readonly property bool trusted: !!repo && repo.trusted === true
    readonly property bool trustable: !!repo && !!repo.identity
    // The Git LFS note under the row: open while this is the view's note
    // (FoamyInfoNote keeps its own `expanded`, so follow it imperatively).
    readonly property bool noteWanted: lfs && !trusted && !unavailable && !!repo && root.lfsNotePath === repo.path
    onNoteWantedChanged: {
      lfsNote.expanded = noteWanted
      if (noteWanted)
        wheel.ensureVisible(lfsPanel)
    }
    Component.onCompleted: lfsNote.expanded = noteWanted
    hasCursor: cursor.at(rowStop)
    onHovered: cursor.hover(rowStop)
    Accessible.role: Accessible.ListItem
    Accessible.name: repo ? String(repo.label) : ""
    Accessible.description: meta + (syncError ? " · " + syncError : "")

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: FoamyStyle.rowPadding
      anchors.leftMargin: FoamyStyle.rowPadding
      anchors.rightMargin: FoamyStyle.gapSmall
      spacing: FoamyStyle.rowPadding

      Rectangle {
        Layout.preferredWidth: 2
        Layout.preferredHeight: FoamyStyle.controlHeight
        radius: FoamyStyle.pillRadius(width)
        color: repoRow.stateColor
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: FoamyStyle.gapTiny
        Text {
          Layout.fillWidth: true
          text: repoRow.repo ? String(repoRow.repo.label) : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignLeft
          color: FoamyPalette.text
          font.family: FoamyStyle.fontFamily
          font.pixelSize: FoamyStyle.font.title
        }
        // Status line, then the last fetch error inline in the error colour:
        // "main · 3 changed · No origin remote configured…" (full text on hover).
        // The error keeps at least 40% of the line, else it gets its own
        // line, so a long branch never hides it.
        Flow {
          id: statusLine
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: 0
          readonly property bool hasError: repoRow.syncError !== "" && !repoRow.unavailable
          readonly property real badgeSpace: lfsBadge.visible ? lfsBadge.width + FoamyStyle.gapSmall : 0
          readonly property bool errorInline: hasError && metaText.implicitWidth + badgeSpace + Math.min(errorMetrics.advanceWidth, width * 0.4) <= width
          TextMetrics {
            id: errorMetrics
            font: errorText.font
            text: " · " + repoRow.syncError
          }
          Text {
            id: metaText
            width: statusLine.errorInline ? implicitWidth : repoRow.unavailable ? statusLine.width : Math.min(implicitWidth, statusLine.width - statusLine.badgeSpace)
            height: Math.max(implicitHeight, lfsBadge.visible ? lfsBadge.height : 0)
            verticalAlignment: Text.AlignVCenter
            text: repoRow.meta
            textFormat: Text.PlainText
            wrapMode: repoRow.unavailable ? Text.WordWrap : Text.NoWrap
            elide: repoRow.unavailable ? Text.ElideNone : Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            color: FoamyPalette.secondaryText
            font.family: FoamyStyle.fontFamily
            font.pixelSize: FoamyStyle.font.bodySmall
          }
          // Git LFS: an "LFS" button that opens a note (with Trust) under the
          // row, or an "LFS" chip once trusted.
          Item {
            id: lfsBadge
            visible: repoRow.lfs && !repoRow.unavailable
            width: (repoRow.trusted ? chip.width : lfsButton.width) + FoamyStyle.gapSmall
            height: repoRow.trusted ? chip.height : lfsButton.height
            Rectangle {
              id: chip
              visible: repoRow.trusted
              x: FoamyStyle.gapSmall
              width: chipText.implicitWidth + FoamyStyle.gap * 2
              height: chipText.implicitHeight + FoamyStyle.gapTiny * 2
              radius: FoamyStyle.pillRadius(height)
              color: Qt.alpha(FoamyPalette.success, 0.16)
              Accessible.role: Accessible.StaticText
              Accessible.name: FoamyI18n.t("Git LFS, trusted")
              Text {
                id: chipText
                anchors.centerIn: parent
                text: FoamyI18n.t("LFS")
                textFormat: Text.PlainText
                color: FoamyPalette.onSurface(FoamyPalette.success)
                font.family: FoamyStyle.fontFamily
                font.pixelSize: FoamyStyle.font.caption
                font.weight: Font.DemiBold
              }
            }
            FoamyAction {
              id: lfsButton
              objectName: "githubLfsButton"
              visible: !repoRow.trusted
              x: FoamyStyle.gapSmall
              implicitHeight: FoamyStyle.iconSize + FoamyStyle.gapSmall * 2
              iconName: "info"
              iconSize: FoamyStyle.iconSize - 2
              label: FoamyI18n.t("LFS")
              foreground: repoRow.noteWanted ? FoamyPalette.text : FoamyPalette.secondaryText
              color: active && (repoRow.noteWanted || hasCursor || hovered) ? FoamyPalette.hoverFill : "transparent"
              hasCursor: cursor.at(repoRow.infoStop)
              Accessible.name: FoamyI18n.t("This repository uses Git LFS")
              Accessible.checkable: true
              Accessible.checked: repoRow.noteWanted
              onHoveredChanged: if (hovered)
                cursor.hover(repoRow.infoStop)
              onClicked: {
                cursor.hover(repoRow.infoStop)
                root.toggleLfsNote(repoRow.repo)
              }
            }
          }
          Text {
            id: errorText
            visible: statusLine.hasError
            width: statusLine.errorInline ? Math.max(0, statusLine.width - metaText.width - statusLine.badgeSpace) : statusLine.width
            text: (statusLine.errorInline ? " · " : "") + repoRow.syncError
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignLeft
            color: FoamyPalette.onSurface(FoamyPalette.error)
            font.family: FoamyStyle.fontFamily
            font.pixelSize: FoamyStyle.font.bodySmall
            Accessible.role: Accessible.AlertMessage
            Accessible.name: repoRow.syncError
            HoverHandler {
              id: errorHover
            }
            PanelToolTip {
              visible: errorHover.hovered && errorText.truncated
              text: repoRow.syncError
              fontFamily: FoamyStyle.fontFamily
            }
          }
        }
      }

      Row {
        spacing: FoamyStyle.gapSmall
        Layout.alignment: Qt.AlignVCenter
        FoamyAction {
          iconName: "arrow-up"
          tooltipText: FoamyI18n.t("Push %1", [repoRow.repo ? String(repoRow.repo.label) : ""])
          enabled: !root.busy && !!repoRow.repo && repoRow.repo.complete === true && repoRow.repo.ahead > 0
          foreground: FoamyPalette.secondaryText
          onClicked: root.service.pushRepository(repoRow.repo)
        }
        FoamyAction {
          iconName: "arrow-down"
          tooltipText: FoamyI18n.t("Pull %1", [repoRow.repo ? String(repoRow.repo.label) : ""])
          enabled: !root.busy && Model.canPull(repoRow.repo)
          foreground: FoamyPalette.secondaryText
          onClicked: root.service.pullRepository(repoRow.repo)
        }
        FoamyAction {
          iconName: "eye"
          tooltipText: FoamyI18n.t("Open in lazygit")
          enabled: !!repoRow.repo
          foreground: FoamyPalette.secondaryText
          onClicked: root.repositoryRequested(repoRow.repo)
        }
      }
    }

    // The Git LFS note, under the status line and in line with it: what the
    // automatic checks skip, and Trust (when this filesystem allows it).
    Column {
      id: lfsPanel
      visible: repoRow.noteWanted
      anchors.top: content.bottom
      anchors.topMargin: FoamyStyle.gap
      anchors.left: parent.left
      anchors.right: parent.right
      // past the state bar
      anchors.leftMargin: FoamyStyle.rowPadding * 2 + 2
      anchors.rightMargin: FoamyStyle.rowPadding
      spacing: FoamyStyle.gap
      FoamyInfoNote {
        id: lfsNote
        width: parent.width
        showHeader: false
        focusable: false
        text: FoamyI18n.t("Automatic checks don't run a repository's own filters, so LFS files you edited may show as changed until Git refreshes.") + (repoRow.trustable ? "" : "\n" + FoamyI18n.t("Trust isn't available for this repository's filesystem."))
      }
      FoamyButton {
        objectName: "githubTrustButton"
        visible: repoRow.trustable
        text: FoamyI18n.t("Trust this repository")
        iconName: "check"
        hasCursor: cursor.at(repoRow.trustStop)
        onHoveredChanged: if (hovered)
          cursor.hover(repoRow.trustStop)
        onClicked: root.activate(repoRow.trustStop)
      }
    }
  }
}
