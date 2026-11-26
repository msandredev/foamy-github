const assert = require('node:assert/strict')
const test = require('node:test')
const Stats = require('../GithubStats.js')

const tr = key => key
const payload = {
  data: {
    viewer: {
      login: 'msandredev',
      repositories: { totalCount: 56 },
      pullRequests: { totalCount: 2 },
      issues: { totalCount: 3 },
      contributionsCollection: {
        totalCommitContributions: 19,
        contributionCalendar: {
          totalContributions: 23,
          weeks: [{ contributionDays: [{ date: '2026-11-25', contributionCount: 4, contributionLevel: 'FOURTH_QUARTILE' }] }]
        }
      }
    }
  }
}

test('the GraphQL query is balanced and asks for every badge field', () => {
  const query = Stats.query()
  assert.equal((query.match(/{/g) || []).length, (query.match(/}/g) || []).length)
  for (const field of ['totalCount', 'pullRequests', 'issues', 'totalCommitContributions', 'contributionCalendar'])
    assert.ok(query.includes(field), field)
})

test('a valid payload populates bounded counts and activity', () => {
  const result = Stats.parse(JSON.stringify(payload), tr)
  assert.equal(result.ok, true)
  assert.deepEqual(result.stats, { repoCount: 56, openPRs: 2, openIssues: 3 })
  assert.equal(result.activity.login, 'msandredev')
  assert.equal(result.activity.weekly.commits, 19)
  assert.equal(result.activity.calendar.total, 23)
  assert.equal(result.activity.calendar.weeks[0][0].level, 4)
})

test('GraphQL errors, missing viewers and oversized output fail closed', () => {
  for (const text of ['', 'not json', JSON.stringify({ errors: [{ message: 'bad' }] }), JSON.stringify({ data: {} }), 'x'.repeat(Stats.MAX_OUTPUT + 1)]) {
    const result = Stats.parse(text, tr)
    assert.equal(result.ok, false)
    assert.equal(result.stats, null)
    assert.match(result.error, /GitHub statistics are unavailable/)
  }
})

test('invalid counts and contributions are clamped, not trusted', () => {
  const broken = JSON.parse(JSON.stringify(payload))
  broken.data.viewer.repositories.totalCount = -3
  broken.data.viewer.pullRequests.totalCount = 'many'
  broken.data.viewer.issues.totalCount = 1e12
  broken.data.viewer.contributionsCollection.contributionCalendar.weeks = [{}]
  const result = Stats.parse(JSON.stringify(broken), tr)
  assert.deepEqual(result.stats, { repoCount: 0, openPRs: 0, openIssues: 0 })
  assert.equal(result.activity.calendar.weeks[0].length, 0)
})
