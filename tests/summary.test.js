const test = require('node:test')
const assert = require('node:assert/strict')
const GithubSummary = require('../GithubSummary.js')

const tr = (key, values) => values
  ? key.replace('%1', values[0]).replace('%2', values[1])
  : key

test('an empty local list with GitHub repos reports both counts', () => {
  assert.equal(GithubSummary.emptyText(0, 56, tr), '0 local · 56 GitHub')
})

test('an empty local list without GitHub repos keeps the old message', () => {
  assert.equal(GithubSummary.emptyText(0, 0, tr), 'No repositories found')
})

test('a non-empty local list does not use the empty branch', () => {
  assert.equal(GithubSummary.emptyText(3, 56, tr), '')
})

test('invalid GitHub counts fail closed', () => {
  assert.equal(GithubSummary.emptyText(0, 'x', tr), 'No repositories found')
  assert.equal(GithubSummary.emptyText(0, -4, tr), 'No repositories found')
})
