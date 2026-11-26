const assert = require('node:assert/strict')
const test = require('node:test')
const Items = require('../GithubItems.js')

const tr = key => key
const pull = {
  number: 12,
  title: 'Fix redirect',
  url: 'https://github.com/octocat/hello-world/pull/12',
  repository: { nameWithOwner: 'octocat/hello-world' },
  author: { login: 'octocat' },
  createdAt: '2026-11-20T10:00:00Z',
  updatedAt: '2026-11-25T10:00:00Z',
  isDraft: true
}

test('the search command bounds the stream before the shell buffers it', () => {
  const pulls = Items.command('pulls')
  assert.deepEqual(pulls.slice(0, 7), ['gh', 'search', 'prs', '--author', '@me', '--state', 'open'])
  assert.deepEqual(pulls.slice(7, 10), ['--sort', 'updated', '--limit'])
  assert.equal(pulls[10], '30')
  assert.match(pulls.at(-1), /^\.\[:30\].*title.*\[0:240\].*url.*\[0:512\].*isDraft/)
  assert.equal(pulls.at(-1).includes("'"), false)
  const issues = Items.command('issues')
  assert.equal(issues[2], 'issues')
  assert.match(issues.at(-1), /^\.\[:30\]/)
  assert.doesNotMatch(issues.at(-1), /isDraft/)
})

test('pulls keep the draft flag and all bounded fields', () => {
  const result = Items.parse(JSON.stringify([pull]), 'pulls', tr)
  assert.equal(result.error, '')
  assert.equal(result.partial, false)
  assert.deepEqual(result.items, [{
    number: 12,
    title: 'Fix redirect',
    url: pull.url,
    repository: 'octocat/hello-world',
    author: 'octocat',
    createdAt: pull.createdAt,
    updatedAt: pull.updatedAt,
    isDraft: true
  }])
})

test('issues ignore the draft flag and fall back to the URL for repository', () => {
  const issue = { ...pull, url: 'https://github.com/octocat/hello-world/issues/9', repository: { nameWithOwner: 'bad value' } }
  delete issue.isDraft
  const result = Items.parse(JSON.stringify([issue]), 'issues', tr)
  assert.equal(result.items[0].repository, 'octocat/hello-world')
  assert.equal(result.items[0].isDraft, false)
})

test('malformed, oversized and non-GitHub input fails closed', () => {
  for (const text of ['', 'not json', '{}', 'x'.repeat(Items.MAX_OUTPUT + 1)])
    assert.match(Items.parse(text, 'pulls', tr).error, /Could not load/)
  const bad = { ...pull, url: 'https://example.com/octocat/hello-world/pull/12' }
  assert.equal(Items.parse(JSON.stringify([bad]), 'pulls', tr).items.length, 0)
})

test('more than the limit is explicitly partial', () => {
  const rows = Array.from({ length: 34 }, (_, i) => ({ ...pull, number: i + 1 }))
  const result = Items.parse(JSON.stringify(rows), 'pulls', tr)
  assert.equal(result.items.length, Items.LIMIT)
  assert.equal(result.partial, true)
})

test('the full-list link always points at github.com', () => {
  assert.equal(Items.searchUrl('pulls'), 'https://github.com/pulls?q=is%3Apr+is%3Aopen+author%3A%40me')
  assert.equal(Items.searchUrl('other'), 'https://github.com/issues?q=is%3Aissue+is%3Aopen+author%3A%40me')
  assert.equal(Items.isValidUrl(pull.url), true)
  assert.equal(Items.isValidUrl('https://github.com.evil.test/a/b/pull/1'), false)
})
