// Pure GraphQL command and parser for the GitHub summary badges. Keeping the
// query here makes the brace balance and the failure contract testable; the
// Service owns the process and publishes a validity flag, never a false zero.
var MAX_OUTPUT = 64 * 1024
var WEEK_LIMIT = 53
var DAY_LIMIT = 7
var DAY_MS = 86400000
var MIN_DAY = Date.UTC(2008, 0, 1)
var MAX_DAY = Date.UTC(2100, 0, 1)

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

function dayMs(value) {
  var text = boundedText(value, 40)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text))
    return -1
  var ms = Date.parse(text + "T00:00:00Z")
  if (!isFinite(ms) || ms < MIN_DAY || ms > MAX_DAY || new Date(ms).toISOString().slice(0, 10) !== text)
    return -1
  return ms
}

function streaks(counts) {
  var indices = []
  for (var key in counts) {
    if (Object.prototype.hasOwnProperty.call(counts, key))
      indices.push(Number(key))
  }
  indices.sort(function (a, b) {
    return a - b
  })
  if (indices.length === 0)
    return { current: 0, longest: 0 }
  var longest = 0
  var run = 0
  var previous = null
  for (var i = 0; i < indices.length; i++) {
    var index = indices[i]
    if (counts[index] > 0) {
      run = previous !== null && index === previous + 1 ? run + 1 : 1
      longest = Math.max(longest, run)
      previous = index
    }
  }
  var end = indices[indices.length - 1]
  if (!(counts[end] > 0))
    end--
  var current = 0
  while (counts[end] > 0) {
    current++
    end--
  }
  return { current: current, longest: longest }
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
  var counts = {}
  var weeks = sourceWeeks.map(function (week) {
    var days = Array.isArray(week && week.contributionDays) ? week.contributionDays.slice(0, DAY_LIMIT) : []
    return days.map(function (day) {
      var text = boundedText(day && day.date, 40)
      var ms = dayMs(text)
      var dayCount = count(day && day.contributionCount)
      if (ms >= 0)
        counts[Math.floor(ms / DAY_MS)] = dayCount
      return {
        date: text,
        count: dayCount,
        level: level(day && day.contributionLevel),
        row: ms >= 0 ? new Date(ms).getUTCDay() : 0
      }
    })
  })
  var streak = streaks(counts)

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
        weeks: weeks,
        streak: streak.current,
        longest: streak.longest
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
    level: level,
    dayMs: dayMs,
    streaks: streaks
  }
}
