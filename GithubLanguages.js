// Pure command builder and parser for the aggregated language bar. The jq
// projection aggregates bytes before Quickshell buffers stdout; the parser
// still validates every field before any value reaches the UI.
var MAX_OUTPUT = 64 * 1024
var MAX_REPOS = 100
var PER_REPO = 10
var MAX_ENTRIES = 32
var MAX_SHOWN = 8
var MAX_NAME = 80
var MAX_COLOR = 16

function query() {
  return "{ viewer { repositories(first: " + String(MAX_REPOS)
    + ", ownerAffiliations: OWNER, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { languages(first: "
    + String(PER_REPO) + ", orderBy: {field: SIZE, direction: DESC}) { edges { size node { name color } } } } } } }"
}

function jq() {
  return "if ((.errors // []) | length) > 0 or (.data.viewer.repositories.nodes | type) != \"array\" then [] else "
    + "[ .data.viewer.repositories.nodes[]?.languages.edges[]? "
    + "| { name: (.node.name // \"\" | tostring | .[0:" + String(MAX_NAME) + "]), "
    + "color: (.node.color // \"\" | tostring | .[0:" + String(MAX_COLOR) + "]), "
    + "size: (.size // 0) } ] "
    + "| group_by(.name) "
    + "| map({ name: .[0].name, color: .[0].color, bytes: (map(.size) | add) }) "
    + "| sort_by(-.bytes) | .[0:" + String(MAX_ENTRIES) + "] end"
}

function command() {
  return ["gh", "api", "graphql", "-f", "query=" + query(), "--jq", jq()]
}

function count(value) {
  var number = Number(value)
  return isFinite(number) && number >= 0 && number <= 1000000000000 ? Math.floor(number) : 0
}

function boundedText(value, limit) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/[\r\n\t]+/g, " ").trim()
  return text.length > limit ? text.slice(0, limit) : text
}

function validColor(value) {
  var color = boundedText(value, MAX_COLOR)
  return color === "" || /^#[0-9a-fA-F]{6}$/.test(color) ? color : ""
}

function parse(text, tr) {
  var translate = typeof tr === "function" ? tr : function (key) { return key }
  var invalid = {
    ok: false,
    languages: [],
    total: 0,
    error: translate("GitHub languages are unavailable.")
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
  if (!Array.isArray(payload) || payload.length > MAX_ENTRIES)
    return invalid

  var byName = {}
  var names = []
  var total = 0
  for (var i = 0; i < payload.length; i++) {
    var entry = payload[i]
    if (!entry || typeof entry !== "object")
      return invalid
    var name = boundedText(entry.name, MAX_NAME)
    var size = count(entry.bytes)
    if (name === "" || size <= 0)
      continue
    var color = validColor(entry.color)
    if (color !== boundedText(entry.color, MAX_COLOR))
      return invalid
    if (!Object.prototype.hasOwnProperty.call(byName, name)) {
      byName[name] = { name: name, color: color, bytes: 0 }
      names.push(name)
    }
    byName[name].bytes += size
    total += size
  }
  if (total <= 0)
    return invalid

  names.sort(function (a, b) {
    return byName[b].bytes - byName[a].bytes || a.localeCompare(b)
  })
  var shown = names.slice(0, MAX_SHOWN).map(function (name) {
    var row = byName[name]
    return {
      name: name,
      color: row.color,
      bytes: row.bytes,
      percent: Math.round(row.bytes * 100 / total)
    }
  })
  var rest = names.slice(MAX_SHOWN).reduce(function (sum, name) {
    return sum + byName[name].bytes
  }, 0)
  if (rest > 0)
    shown.push({
      name: translate("Other"),
      color: "",
      bytes: rest,
      percent: Math.round(rest * 100 / total)
    })

  return { ok: true, languages: shown, total: total, error: "" }
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_OUTPUT: MAX_OUTPUT,
    MAX_SHOWN: MAX_SHOWN,
    query: query,
    jq: jq,
    command: command,
    parse: parse,
    count: count,
    validColor: validColor
  }
}
