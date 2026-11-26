// Pure parsing and command construction for the Pull requests / Issues page.
// `gh search` output is untrusted: fields are bounded by the command's --jq
// before StdioCollector buffers them, then checked again here before any UI
// can hand a URL to the browser. No QML pragma: the tests require this file.
var LIMIT = 30
var MAX_OUTPUT = 64 * 1024

function clean(value, limit) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/[\r\n\t]+/g, " ").trim()
  return text.length > limit ? text.slice(0, limit) : text
}

function isValidUrl(url) {
  return /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/(?:pull|issues)\/\d+\/?$/.test(String(url || ""))
}

function repoFromUrl(url) {
  var match = /^https:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/(?:pull|issues)\/\d+/.exec(String(url || ""))
  return match ? match[1] + "/" + match[2] : ""
}

// The jq projection truncates each field before the shell buffers the stream,
// and `.[:30]` makes the count limit hold even if gh's own --limit changes.
function command(section) {
  var pulls = section === "pulls"
  var fields = "number,title,url,repository,author,createdAt,updatedAt" + (pulls ? ",isDraft" : "")
  var draft = pulls ? ', isDraft: (.isDraft == true)' : ""
  // The expression is one argv element, not a shell line: wrapping quotes
  // would be passed to jq literally and fail to parse.
  var projection = ".[:" + LIMIT + "] | map({number, title: ((.title // \"\")[0:240]), "
    + "url: ((.url // \"\")[0:512]), repository: {nameWithOwner: ((.repository.nameWithOwner // \"\")[0:120])}, "
    + "author: {login: ((.author.login // \"\")[0:64])}, createdAt: ((.createdAt // \"\")[0:40]), "
    + "updatedAt: ((.updatedAt // \"\")[0:40])" + draft + "})"
  return ["gh", "search", pulls ? "prs" : "issues", "--author", "@me",
    "--state", "open", "--sort", "updated", "--limit", String(LIMIT),
    "--json", fields, "--jq", projection]
}

function parse(text, section, tr) {
  var translate = typeof tr === "function" ? tr : function (key) { return key }
  var invalid = { items: [], error: translate("Could not load GitHub items."), partial: false }
  var source = String(text === undefined || text === null ? "" : text).trim()
  if (source === "" || source.length > MAX_OUTPUT)
    return invalid

  var parsed
  try {
    parsed = JSON.parse(source)
  } catch (error) {
    return invalid
  }
  if (!Array.isArray(parsed))
    return invalid

  var pulls = section === "pulls"
  var items = []
  for (var i = 0; i < parsed.length && items.length < LIMIT; i++) {
    var entry = parsed[i] || {}
    var url = clean(entry.url, 512)
    if (!isValidUrl(url))
      continue

    var repo = clean(entry.repository && entry.repository.nameWithOwner, 120)
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo))
      repo = repoFromUrl(url)
    var author = clean(entry.author && entry.author.login, 64)
    if (!/^[A-Za-z0-9-]+$/.test(author))
      author = ""

    var number = Number(entry.number)
    var createdAt = clean(entry.createdAt, 40)
    var updatedAt = clean(entry.updatedAt, 40)
    items.push({
      number: isFinite(number) && number > 0 && number <= 1000000000 ? Math.floor(number) : 0,
      title: clean(entry.title, 240),
      url: url,
      repository: repo,
      author: author,
      createdAt: isFinite(Date.parse(createdAt)) ? createdAt : "",
      updatedAt: isFinite(Date.parse(updatedAt)) ? updatedAt : "",
      isDraft: pulls && entry.isDraft === true
    })
  }
  return { items: items, error: "", partial: parsed.length > LIMIT }
}

function searchUrl(section) {
  return section === "pulls"
    ? "https://github.com/pulls?q=is%3Apr+is%3Aopen+author%3A%40me"
    : "https://github.com/issues?q=is%3Aissue+is%3Aopen+author%3A%40me"
}

if (typeof module !== "undefined") {
  module.exports = {
    LIMIT: LIMIT,
    clean: clean,
    isValidUrl: isValidUrl,
    repoFromUrl: repoFromUrl,
    command: command,
    parse: parse,
    searchUrl: searchUrl
  }
}
