pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "kit"
import "GithubStats.js" as GithubStats

// The contribution calendar from GithubStats.js: 53 columns of seven days,
// sized to fit the popup instead of scrolling. Kept in its own file so the
// activity page can show it without inflating the repository list.
Column {
  id: root
  property var graph: null
  readonly property var type: FoamyStyle.font
  readonly property var weeks: graph && graph.weeks ? graph.weeks : []
  readonly property int total: graph ? Number(graph.total || 0) : 0
  spacing: FoamyStyle.gapSmall

  function formatDay(value) {
    var ms = GithubStats.dayMs(value)
    if (ms < 0)
      return String(value || "")
    var day = new Date(ms)
    return Qt.locale().monthName(day.getUTCMonth(), Locale.ShortFormat) + " " + day.getUTCDate() + ", " + day.getUTCFullYear()
  }

  RowLayout {
    width: parent.width
    spacing: FoamyStyle.gapSmall
    Text {
      Layout.fillWidth: true
      text: FoamyI18n.t("%1 contributions in the last year", [FoamyI18n.number(root.total)])
      textFormat: Text.PlainText
      color: FoamyPalette.secondaryText
      font.family: FoamyStyle.fontFamily
      font.pixelSize: root.type.caption
    }
    Row {
      spacing: 3
      Text {
        text: FoamyI18n.t("Less")
        color: FoamyPalette.mutedText
        font.family: FoamyStyle.fontFamily
        font.pixelSize: root.type.caption
        anchors.verticalCenter: parent.verticalCenter
      }
      Repeater {
        model: [0, 1, 2, 3, 4]
        Rectangle {
          required property int modelData
          width: 8
          height: 8
          radius: 2
          color: modelData === 0 ? Qt.alpha(FoamyPalette.text, 0.08) : modelData === 1 ? Qt.alpha(FoamyPalette.success, 0.28) : modelData === 2 ? Qt.alpha(FoamyPalette.success, 0.48) : modelData === 3 ? Qt.alpha(FoamyPalette.success, 0.72) : FoamyPalette.success
        }
      }
      Text {
        text: FoamyI18n.t("More")
        color: FoamyPalette.mutedText
        font.family: FoamyStyle.fontFamily
        font.pixelSize: root.type.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  Item {
    id: heatmap
    width: parent.width
    readonly property int weekCount: root.weeks.length
    readonly property int gap: width >= 360 ? 2 : 1
    readonly property int cell: Math.max(1, Math.min(12, Math.floor((width + gap) / Math.max(weekCount, 1)) - gap))
    readonly property int step: cell + gap
    readonly property int plotWidth: Math.max(0, Math.min(width, weekCount * step - gap))
    readonly property int monthHeight: monthFont.height
    property string hoverDate: ""
    property int hoverCount: 0
    height: monthHeight + FoamyStyle.gapTiny + cell * 7 + gap * 6

    function monthLabels(weeks) {
      let labels = []
      let previous = ""
      for (let i = 0; i < weeks.length; i++) {
        let week = weeks[i]
        if (!week || !week.length)
          continue
        let date = ""
        let month = ""
        for (let j = 0; j < week.length; j++) {
          let candidate = String(week[j] && week[j].date || "")
          let candidateMonth = candidate.slice(0, 7)
          if (candidateMonth !== "" && candidateMonth !== previous) {
            date = candidate
            month = candidateMonth
            break
          }
        }
        if (month === "")
          continue
        previous = month
        let name = Qt.locale().monthName(Number(date.slice(5, 7)) - 1, Locale.ShortFormat)
        let labelWidth = Math.ceil(monthFont.advanceWidth(name))
        let left = Math.max(0, Math.min(i * heatmap.step, heatmap.plotWidth - labelWidth))
        if (labels.length && left < labels[labels.length - 1].left + labels[labels.length - 1].width + FoamyStyle.gapSmall)
          continue
        labels.push({
          month: month,
          name: name,
          left: left,
          width: labelWidth
        })
      }
      return labels
    }

    FontMetrics {
      id: monthFont
      font.family: FoamyStyle.fontFamily
      font.pixelSize: root.type.caption
    }

    Repeater {
      model: heatmap.monthLabels(root.weeks)
      Text {
        required property var modelData
        x: modelData.left
        y: 0
        width: modelData.width
        text: modelData.name
        textFormat: Text.PlainText
        color: FoamyPalette.mutedText
        font.family: FoamyStyle.fontFamily
        font.pixelSize: root.type.caption
      }
    }

    Row {
      y: heatmap.monthHeight + FoamyStyle.gapTiny
      spacing: heatmap.gap
      Repeater {
        model: root.weeks
        delegate: Item {
          id: weekColumn
          required property var modelData
          width: heatmap.cell
          height: heatmap.cell * 7 + heatmap.gap * 6

          Repeater {
            model: weekColumn.modelData
            delegate: Rectangle {
              id: dayCell
              required property var modelData
              width: heatmap.cell
              height: width
              y: Number(modelData.row || 0) * heatmap.step
              radius: width > 4 ? 2 : 0
              color: {
                var l = Number(modelData.level || 0)
                return l <= 0 ? Qt.alpha(FoamyPalette.text, 0.08) : l === 1 ? Qt.alpha(FoamyPalette.success, 0.28) : l === 2 ? Qt.alpha(FoamyPalette.success, 0.48) : l === 3 ? Qt.alpha(FoamyPalette.success, 0.72) : FoamyPalette.success
              }
              HoverHandler {
                id: dayHover
                onHoveredChanged: {
                  if (hovered) {
                    heatmap.hoverDate = dayCell.modelData.date
                    heatmap.hoverCount = dayCell.modelData.count
                  } else if (heatmap.hoverDate === dayCell.modelData.date) {
                    heatmap.hoverDate = ""
                    heatmap.hoverCount = 0
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Text {
    width: parent.width
    visible: heatmap.hoverDate !== ""
    text: FoamyI18n.t("%1 contributions on %2", [FoamyI18n.number(heatmap.hoverCount), root.formatDay(heatmap.hoverDate)])
    textFormat: Text.PlainText
    color: FoamyPalette.secondaryText
    font.family: FoamyStyle.fontFamily
    font.pixelSize: root.type.caption
  }
}
