pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "kit"
import "Model.js" as Model
import "GithubItems.js" as GithubItems

// Pull requests / Issues page for the GitHub popup. It owns its own bounded
// `gh search` request so Service.qml (which carries uncommitted user work)
// stays untouched. Results are parsed and URL-checked in GithubItems.js.
Item {
  id: root
  objectName: "githubItemsPage"

  property string section: "repos" // repos, pulls, issues
  property var items: []
  property string error: ""
  property bool loading: false
  property bool partial: false
  property int itemCursor: 0
  property bool componentReady: false
  property int requestId: 0

  readonly property string title: root.section === "pulls" ? FoamyI18n.t("Pull requests") : FoamyI18n.t("Issues")
  // The font tokens live in a QtObject; expose a dynamically typed handle so
  // static analysis can follow the same token source.
  readonly property var type: FoamyStyle.font

  signal backRequested

  focus: true

  function open(url) {
    if (GithubItems.isValidUrl(url))
      Qt.openUrlExternally(String(url))
  }

  // One completion path for success, failure, cancellation and destruction.
  // The generation check drops a late reply after a section switch.
  function finish(id, exitCode) {
    if (!root.loading || id !== root.requestId)
      return
    root.loading = false
    deadline.stop()
    // A timed-out process is still a child of the shell; stop it so Retry can
    // start a fresh one and no late stdout can be mistaken for a new reply.
    itemsProcess.operationId = -1
    itemsProcess.running = false
    if (exitCode !== 0) {
      root.items = []
      root.partial = false
      root.error = FoamyI18n.t("Could not load GitHub items.")
      return
    }
    var result = GithubItems.parse(itemsOutput.text, root.section, FoamyI18n.t)
    root.items = result.items
    root.error = result.error
    root.partial = result.partial
  }

  function reload() {
    if (!root.componentReady || root.section === "repos" || itemsProcess.running)
      return
    root.requestId++
    root.error = ""
    root.partial = false
    root.items = []
    root.itemCursor = 0
    root.loading = true
    var id = root.requestId
    itemsProcess.command = GithubItems.command(root.section)
    itemsProcess.operationId = id
    itemsProcess.running = true
    deadline.restart()
    // Quickshell may not emit `exited` when a command fails to start.
    Qt.callLater(function () {
      if (root.loading && id === root.requestId && !itemsProcess.running)
        root.finish(id, -1)
    })
  }

  function move(dy) {
    if (root.items.length === 0)
      return
    root.itemCursor = Math.max(0, Math.min(root.items.length - 1, root.itemCursor + dy))
    list.positionViewAtIndex(root.itemCursor, ListView.Contain)
  }

  function activateAt(index) {
    if (index < 0 || index >= root.items.length)
      return
    root.itemCursor = index
    root.open(root.items[index].url)
  }

  function activate() {
    root.activateAt(root.itemCursor)
  }

  onSectionChanged: {
    if (!root.componentReady)
      return
    root.requestId++
    itemsProcess.operationId = -1
    itemsProcess.running = false
    deadline.stop()
    root.items = []
    root.error = ""
    root.partial = false
    root.loading = false
    root.itemCursor = 0
    if (root.section !== "repos")
      root.reload()
  }
  onItemsChanged: if (root.itemCursor >= root.items.length)
    root.itemCursor = 0

  Component.onCompleted: {
    root.componentReady = true
    if (root.section !== "repos")
      root.reload()
  }
  Component.onDestruction: {
    root.componentReady = false
    root.requestId++
    itemsProcess.operationId = -1
    itemsProcess.running = false
    deadline.stop()
  }

  Process {
    id: itemsProcess
    // Ties an exit signal to the request that started it. A cancelled
    // process can still report an exit after the next request has started.
    property int operationId: -1
    stdout: StdioCollector {
      id: itemsOutput
      waitForEnd: true
    }
    // Keep gh's own diagnostics out of the shell log without buffering them.
    stderr: SplitParser {
      splitMarker: ""
      onRead: function (data) {
        void data
      }
    }

    onExited: function (exitCode) {
      root.finish(itemsProcess.operationId, exitCode)
    }
  }

  Timer {
    id: deadline
    interval: 20000
    repeat: false
    onTriggered: root.finish(root.requestId, -1)
  }

  Column {
    anchors.fill: parent
    spacing: FoamyStyle.gap

    Row {
      id: pageHeader
      width: parent.width
      height: FoamyStyle.controlHeight
      spacing: FoamyStyle.gapSmall

      FoamyAction {
        id: back
        iconName: "arrow-left"
        tooltipText: FoamyI18n.t("Back to repositories")
        foreground: FoamyPalette.secondaryText
        onClicked: root.backRequested()
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - back.width - openAll.width - pageHeader.spacing * 2)
        text: root.title
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: FoamyPalette.text
        font.family: FoamyStyle.fontFamily
        font.pixelSize: root.type.title
        font.weight: Font.DemiBold
      }
      FoamyAction {
        id: openAll
        iconName: "external-link"
        tooltipText: FoamyI18n.t("Open on GitHub")
        foreground: FoamyPalette.secondaryText
        onClicked: root.open(GithubItems.searchUrl(root.section))
      }
    }

    Text {
      id: loadingNote
      visible: root.loading
      width: parent.width
      text: FoamyI18n.t("Loading…")
      textFormat: Text.PlainText
      color: FoamyPalette.secondaryText
      font.family: FoamyStyle.fontFamily
      font.pixelSize: root.type.bodySmall
    }

    Rectangle {
      id: stateNote
      visible: !root.loading && (root.error !== "" || root.items.length === 0)
      width: parent.width
      radius: FoamyStyle.radiusSmall
      color: FoamyPalette.noteFill

      readonly property string message: root.error !== "" ? root.error : root.section === "pulls" ? FoamyI18n.t("No open pull requests.") : FoamyI18n.t("No open issues.")

      height: noteText.implicitHeight + noteButton.implicitHeight + FoamyStyle.gapLarge * 2 + FoamyStyle.gap

      Text {
        id: noteText
        x: FoamyStyle.gapLarge
        y: FoamyStyle.gapLarge
        width: parent.width - FoamyStyle.gapLarge * 2
        text: stateNote.message
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.error !== "" ? FoamyPalette.onSurface(FoamyPalette.error) : FoamyPalette.secondaryText
        font.family: FoamyStyle.fontFamily
        font.pixelSize: root.type.bodySmall
      }
      FoamyButton {
        id: noteButton
        x: FoamyStyle.gapLarge
        anchors.top: noteText.bottom
        anchors.topMargin: FoamyStyle.gap
        width: Math.min(parent.width - FoamyStyle.gapLarge * 2, implicitWidth)
        text: root.error !== "" ? FoamyI18n.t("Try again") : FoamyI18n.t("Open on GitHub")
        iconName: root.error !== "" ? "refresh-cw" : "external-link"
        onClicked: {
          if (root.error !== "")
            root.reload()
          else
            root.open(GithubItems.searchUrl(root.section))
        }
      }
    }

    Text {
      id: partialNote
      visible: !root.loading && root.error === "" && root.items.length > 0 && root.partial
      width: parent.width
      text: FoamyI18n.t("Showing the 30 most recent.")
      textFormat: Text.PlainText
      color: FoamyPalette.mutedText
      font.family: FoamyStyle.fontFamily
      font.pixelSize: root.type.bodySmall
    }

    ListView {
      id: list
      visible: !root.loading && root.error === "" && root.items.length > 0
      width: parent.width
      height: Math.max(0, parent.height - pageHeader.height - FoamyStyle.gap * 2 - (loadingNote.visible ? loadingNote.implicitHeight : 0) - (stateNote.visible ? stateNote.height : 0) - (partialNote.visible ? partialNote.implicitHeight : 0))
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      cacheBuffer: 0
      model: root.items
      FoamyWheelScroll {
        target: list
      }

      delegate: FoamyCursorSurface {
        id: row
        required property var modelData
        required property int index

        width: list.width
        height: FoamyStyle.rowPadding * 2 + title.height + FoamyStyle.gapTiny + meta.height
        hasCursor: root.itemCursor === row.index
        onHovered: root.itemCursor = row.index
        onClicked: root.activateAt(row.index)

        Text {
          id: title
          x: FoamyStyle.rowPadding
          y: FoamyStyle.rowPadding
          width: parent.width - FoamyStyle.rowPadding * 2 - FoamyStyle.iconSize - FoamyStyle.gapSmall
          height: implicitHeight
          text: row.modelData.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          maximumLineCount: 1
          color: FoamyPalette.text
          font.family: FoamyStyle.fontFamily
          font.pixelSize: root.type.body
          font.weight: Font.DemiBold
        }
        Row {
          id: meta
          x: FoamyStyle.rowPadding
          anchors.top: title.bottom
          anchors.topMargin: FoamyStyle.gapTiny
          width: parent.width - FoamyStyle.rowPadding * 2
          height: Math.max(repositoryLabel.implicitHeight, numberLabel.implicitHeight, draftLabel.implicitHeight, authorLabel.implicitHeight)
          spacing: FoamyStyle.gapSmall

          Text {
            id: repositoryLabel
            width: Math.min(Math.floor(parent.width * 0.4), implicitWidth)
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.repository
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: FoamyPalette.secondaryText
            font.family: FoamyStyle.fontFamily
            font.pixelSize: root.type.bodySmall
          }
          Text {
            id: numberLabel
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.number ? "#" + FoamyI18n.number(row.modelData.number) : ""
            textFormat: Text.PlainText
            color: FoamyPalette.mutedText
            font.family: FoamyStyle.monoFamily
            font.pixelSize: root.type.bodySmall
          }
          Text {
            id: draftLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: row.modelData.isDraft
            text: row.modelData.isDraft ? FoamyI18n.t("Draft") : ""
            textFormat: Text.PlainText
            color: FoamyPalette.info
            font.family: FoamyStyle.fontFamily
            font.pixelSize: root.type.bodySmall
          }
          Text {
            id: authorLabel
            width: Math.max(0, parent.width - repositoryLabel.width - numberLabel.width - (draftLabel.visible ? draftLabel.width : 0) - parent.spacing * (draftLabel.visible ? 3 : 2))
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.updatedAt ? (row.modelData.author ? "@" + row.modelData.author + " · " : "") + Model.relativeTime(Date.parse(row.modelData.updatedAt) / 1000, Date.now(), FoamyI18n.t) : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            color: FoamyPalette.mutedText
            font.family: FoamyStyle.fontFamily
            font.pixelSize: root.type.bodySmall
          }
        }
        FoamyIcon {
          anchors.right: parent.right
          anchors.rightMargin: FoamyStyle.rowPadding
          anchors.verticalCenter: parent.verticalCenter
          name: "external-link"
          width: FoamyStyle.iconSize
          height: width
          color: FoamyPalette.secondaryText
        }
      }
    }
  }
}
