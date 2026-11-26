// Shared header wording for the repository counts. Kept as plain JavaScript so
// the decision has a test that fails without it; no QML pragma is needed.
function emptyText(localCount, githubCount, tr) {
  var local = Math.max(0, Number(localCount) || 0)
  var github = Math.max(0, Number(githubCount) || 0)
  var translate = typeof tr === "function" ? tr : function (key) { return key }
  if (local > 0) return ""
  if (github > 0) return translate("%1 local · %2 GitHub", [String(local), String(github)])
  return translate("No repositories found")
}

if (typeof module !== "undefined") {
  module.exports = { emptyText: emptyText }
}
