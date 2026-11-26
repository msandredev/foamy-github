pragma ComponentBehavior: Bound
import QtQuick
import "kit"

// Activity and language detail page for the GitHub popup. Data is owned by
// Service (stats are already fetched for the badges; languages have their own
// bounded GraphQL request), so switching sections cannot lose a reply.
Item {
  id: root
  objectName: "githubActivityPage"

  // var keeps the mock in preview/tests and the Service singleton interchangeable.
  property var service: null
  property bool active: false
  readonly property var type: FoamyStyle.font

  readonly property bool statsValid: !!root.service && root.service.githubEnabled !== false && !!root.service.githubStatsValid
  readonly property var activity: root.statsValid && root.service.githubActivity ? root.service.githubActivity : ({})
  readonly property string statsError: root.service && String(root.service.githubStatsError || "") !== "" ? String(root.service.githubStatsError) : FoamyI18n.t("GitHub statistics are unavailable.")
  readonly property bool languagesLoading: !!root.service && !!root.service.githubLanguagesRefreshing
  readonly property bool languagesValid: !!root.service && root.service.githubEnabled !== false && !!root.service.githubLanguagesValid
  readonly property var languages: root.languagesValid && root.service.githubLanguages ? root.service.githubLanguages.languages || [] : []
  readonly property string languagesError: !root.languagesValid && !!root.service && root.service.githubEnabled !== false && String(root.service.githubLanguagesError || "") !== "" ? String(root.service.githubLanguagesError) : !root.languagesValid ? FoamyI18n.t("GitHub languages are unavailable.") : ""
  readonly property string languageSummary: root.languages.map(function (language) {
    return language.name + " " + FoamyI18n.number(language.percent) + "%"
  }).join(", ")
  // Rounded percentages may not add to exactly 100; cumulative boundaries
  // keep the bar filled edge to edge without stretching the last segment.
  readonly property var segments: {
    let out = []
    let start = 0
    for (let i = 0; i < root.languages.length; i++) {
      let end = i === root.languages.length - 1 ? 100 : Math.min(100, start + Number(root.languages[i].percent || 0))
      out.push({
        language: root.languages[i],
        start: start,
        width: Math.max(0, end - start)
      })
      start = end
    }
    return out
  }

  signal backRequested

  focus: true

  function reload(force) {
    if (!root.service || root.service.githubEnabled === false)
      return
    if (!force && (root.languagesLoading || root.languagesValid))
      return
    root.service.refreshGithubLanguages(!!force)
  }

  function move(dy) {
    if (dy === 0)
      return
    var max = Math.max(0, scroll.contentHeight - scroll.height)
    scroll.contentY = Math.max(0, Math.min(max, scroll.contentY + dy * FoamyStyle.rowHeight))
  }

  function activate() {
    if (root.languagesError !== "")
      root.reload(true)
  }

  onActiveChanged: if (root.active)
    root.reload(false)
  Component.onCompleted: if (root.active)
    root.reload(false)

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
        width: Math.max(0, parent.width - back.width - refreshAction.width - pageHeader.spacing * 2)
        text: FoamyI18n.t("Activity & languages")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: FoamyPalette.text
        font.family: FoamyStyle.fontFamily
        font.pixelSize: root.type.title
        font.weight: Font.DemiBold
      }
      FoamyAction {
        id: refreshAction
        iconName: "refresh-cw"
        tooltipText: FoamyI18n.t("Refresh languages")
        foreground: FoamyPalette.secondaryText
        actionEnabled: !!root.service && root.service.githubEnabled !== false
        onClicked: root.reload(true)
      }
    }

    Flickable {
      id: scroll
      width: parent.width
      height: Math.max(0, parent.height - pageHeader.height - FoamyStyle.gap)
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      FoamyWheelScroll {
        target: scroll
      }

      Column {
        id: content
        width: scroll.width
        spacing: FoamyStyle.gapLarge

        Column {
          width: parent.width
          spacing: FoamyStyle.gapSmall

          Text {
            width: parent.width
            text: FoamyI18n.t("Activity")
            textFormat: Text.PlainText
            color: FoamyPalette.text
            font.family: FoamyStyle.fontFamily
            font.pixelSize: root.type.body
            font.weight: Font.DemiBold
          }
          ContributionGraph {
            visible: root.statsValid
            width: parent.width
            graph: root.activity.calendar || null
          }
          Row {
            visible: root.statsValid && !!root.activity.calendar
            width: parent.width
            spacing: FoamyStyle.gapLarge

            Text {
              text: FoamyI18n.t("Current streak: %1 days", [FoamyI18n.number(Number(root.activity.calendar && root.activity.calendar.streak || 0))])
              textFormat: Text.PlainText
              color: FoamyPalette.secondaryText
              font.family: FoamyStyle.fontFamily
              font.pixelSize: root.type.caption
            }
            Text {
              text: FoamyI18n.t("Longest streak: %1 days", [FoamyI18n.number(Number(root.activity.calendar && root.activity.calendar.longest || 0))])
              textFormat: Text.PlainText
              color: FoamyPalette.mutedText
              font.family: FoamyStyle.fontFamily
              font.pixelSize: root.type.caption
            }
          }
          Rectangle {
            visible: !root.statsValid
            width: parent.width
            radius: FoamyStyle.radiusSmall
            color: FoamyPalette.noteFill
            height: activityNote.implicitHeight + FoamyStyle.gapLarge * 2

            Text {
              id: activityNote
              x: FoamyStyle.gapLarge
              y: FoamyStyle.gapLarge
              width: parent.width - FoamyStyle.gapLarge * 2
              text: root.statsError
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: FoamyPalette.onSurface(FoamyPalette.error)
              font.family: FoamyStyle.fontFamily
              font.pixelSize: root.type.bodySmall
            }
          }
        }

        Column {
          width: parent.width
          spacing: FoamyStyle.gapSmall

          Text {
            width: parent.width
            text: FoamyI18n.t("Languages")
            textFormat: Text.PlainText
            color: FoamyPalette.text
            font.family: FoamyStyle.fontFamily
            font.pixelSize: root.type.body
            font.weight: Font.DemiBold
          }
          Text {
            visible: root.languagesLoading
            width: parent.width
            text: FoamyI18n.t("Loading…")
            textFormat: Text.PlainText
            color: FoamyPalette.secondaryText
            font.family: FoamyStyle.fontFamily
            font.pixelSize: root.type.bodySmall
          }
          Rectangle {
            visible: !root.languagesLoading && (root.languagesError !== "" || root.languages.length === 0)
            width: parent.width
            radius: FoamyStyle.radiusSmall
            color: FoamyPalette.noteFill
            height: languageNote.implicitHeight + retryButton.implicitHeight + FoamyStyle.gapLarge * 2 + FoamyStyle.gap

            Text {
              id: languageNote
              x: FoamyStyle.gapLarge
              y: FoamyStyle.gapLarge
              width: parent.width - FoamyStyle.gapLarge * 2
              text: root.languagesError !== "" ? root.languagesError : FoamyI18n.t("No language data.")
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.languagesError !== "" ? FoamyPalette.onSurface(FoamyPalette.error) : FoamyPalette.secondaryText
              font.family: FoamyStyle.fontFamily
              font.pixelSize: root.type.bodySmall
            }
            FoamyButton {
              id: retryButton
              x: FoamyStyle.gapLarge
              anchors.top: languageNote.bottom
              anchors.topMargin: FoamyStyle.gap
              width: Math.min(parent.width - FoamyStyle.gapLarge * 2, implicitWidth)
              text: FoamyI18n.t("Try again")
              iconName: "refresh-cw"
              actionEnabled: !!root.service && root.service.githubEnabled !== false
              onClicked: root.reload(true)
            }
          }
          Column {
            visible: !root.languagesLoading && root.languagesError === "" && root.languages.length > 0
            width: parent.width
            spacing: FoamyStyle.gapSmall

            Rectangle {
              id: bar
              width: parent.width
              height: FoamyStyle.gapLarge
              radius: FoamyStyle.radiusSmall
              color: FoamyPalette.fieldFill
              clip: true
              Accessible.name: root.languageSummary

              Row {
                anchors.fill: parent
                Repeater {
                  model: root.segments
                  Rectangle {
                    id: segment
                    required property var modelData
                    x: bar.width * segment.modelData.start / 100
                    width: bar.width * segment.modelData.width / 100
                    height: parent.height
                    color: segment.modelData.language.color !== "" ? segment.modelData.language.color : FoamyPalette.secondaryText
                    border.width: 1
                    border.color: FoamyPalette.background
                  }
                }
              }
            }
            Grid {
              id: legendGrid
              width: parent.width
              columns: width < FoamyStyle.unitWidth * 10 ? 1 : 2
              spacing: FoamyStyle.gapSmall
              Accessible.name: root.languageSummary
              Repeater {
                model: root.languages
                Row {
                  id: legendRow
                  required property var modelData
                  width: Math.floor((legendGrid.width - (legendGrid.columns - 1) * legendGrid.spacing) / legendGrid.columns)
                  spacing: FoamyStyle.gapTiny

                  Rectangle {
                    width: FoamyStyle.gap
                    height: FoamyStyle.gap
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 2
                    color: legendRow.modelData.color !== "" ? legendRow.modelData.color : FoamyPalette.secondaryText
                  }
                  Text {
                    width: Math.max(0, parent.width - FoamyStyle.gap * 3 - percentText.implicitWidth)
                    anchors.verticalCenter: parent.verticalCenter
                    text: legendRow.modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: FoamyPalette.secondaryText
                    font.family: FoamyStyle.fontFamily
                    font.pixelSize: root.type.bodySmall
                  }
                  Text {
                    id: percentText
                    anchors.verticalCenter: parent.verticalCenter
                    text: FoamyI18n.t("%1%", [FoamyI18n.number(legendRow.modelData.percent)])
                    textFormat: Text.PlainText
                    color: FoamyPalette.mutedText
                    font.family: FoamyStyle.monoFamily
                    font.pixelSize: root.type.bodySmall
                  }
                }
              }
            }
            Text {
              width: parent.width
              text: FoamyI18n.t("Based on up to 100 repositories")
              textFormat: Text.PlainText
              color: FoamyPalette.mutedText
              font.family: FoamyStyle.fontFamily
              font.pixelSize: root.type.caption
            }
          }
        }
      }
    }
  }
}
