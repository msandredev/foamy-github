// Pure GraphQL command and parser for the GitHub summary badges. Keeping the
// query here makes the brace balance and the failure contract testable; the
// Service owns the process and publishes a validity flag, never a false zero.
var MAX_OUTPUT = 64 * 1024
var WEEK_LIMIT = 53
var DAY_LIMIT = 7

function query() {
  return "{ viewer { login "
    + "repositories(ownerAffiliations: OWNER, first: 1) { totalCount } "
    + "pullRequests(states: OPEN) { totalCount } "
    + "issues(states: OPEN) { totalCount } "
    + "contributionsCollection { totalCommitContributions "
    + "contributionCalendar { totalContributions weeks { contributionDays { date contributionCount contributionLevel } } } } "
    + "} }"
}

function count(value) {
  var number = Number(value)
  return isFinite(number) && number >= 0 && number <= 1000000000 ? Math.floor(number) : 0
}

function boundedText(value, limit) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/[\r\n\t]+/g, " ").trim()
  return text.length > limit ? text.slice(0, limit) : text
}

function level(value) {
  var text = String(value || "")
  if (text.indexOf("FOURTH") !== -1) return 4
  if (text.indexOf("THIRD") !== -1) return 3
  if (text.indexOf("SECOND") !== -1) return 2
  if (text.indexOf("FIRST") !== -1) return 1
  return 0
}

function parse(text, tr) {
  var translate = typeof tr === "function" ? tr : function (key) { return key }
  var invalid = {
    ok: false,
    stats: null,
    activity: null,
    error: translate("GitHub statistics are unavailable.")
  }
  var source = String(text === undefined || text === null ? "" : text).trim()
  if (source === "" || source.length > MAX_OUTPUT)
    return invalid

  var payload
  try {
    payload = JSON.parse(source)
  } catch (error) {
    return invalid
  }
  if (!payload || typeof payload !== "object" || (Array.isArray(payload.errors) && payload.errors.length > 0))
    return invalid
  var viewer = payload.data && payload.data.viewer ? payload.data.viewer : null
  if (!viewer || typeof viewer !== "object")
    return invalid

  var cc = viewer.contributionsCollection || {}
  var calendar = cc.contributionCalendar || {}
  var sourceWeeks = Array.isArray(calendar.weeks) ? calendar.weeks.slice(0, WEEK_LIMIT) : []
  var weeks = sourceWeeks.map(function (week) {
    var days = Array.isArray(week && week.contributionDays) ? week.contributionDays.slice(0, DAY_LIMIT) : []
    return days.map(function (day) {
      return {
        date: boundedText(day && day.date, 40),
        count: count(day && day.contributionCount),
        level: level(day && day.contributionLevel)
      }
    })
  })

  return {
    ok: true,
    stats: {
      repoCount: count(viewer.repositories && viewer.repositories.totalCount),
      openPRs: count(viewer.pullRequests && viewer.pullRequests.totalCount),
      openIssues: count(viewer.issues && viewer.issues.totalCount)
    },
    activity: {
      login: boundedText(viewer.login, 64),
      weekly: { commits: count(cc.totalCommitContributions) },
      calendar: {
        total: count(calendar.totalContributions),
        weeks: weeks
      }
    },
    error: ""
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_OUTPUT: MAX_OUTPUT,
    query: query,
    parse: parse,
    count: count,
    level: level
  }
}
