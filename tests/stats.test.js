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
  assert.equal(result.activity.calendar.weeks[0][0].row, 3)
})

test('the calendar derives weekday rows, streaks and rejects impossible dates', () => {
  const source = JSON.parse(JSON.stringify(payload))
  const days = [
    { date: '2026-11-20', contributionCount: 0, contributionLevel: 'NONE' },
    { date: '2026-11-21', contributionCount: 1, contributionLevel: 'FIRST_QUARTILE' },
    { date: '2026-11-22', contributionCount: 2, contributionLevel: 'SECOND_QUARTILE' },
    { date: '2026-11-23', contributionCount: 3, contributionLevel: 'THIRD_QUARTILE' },
    { date: '2026-11-25', contributionCount: 0, contributionLevel: 'NONE' },
    { date: '2026-02-31', contributionCount: 9, contributionLevel: 'FOURTH_QUARTILE' }
  ]
  source.data.viewer.contributionsCollection.contributionCalendar.weeks = [{ contributionDays: days }]
  const result = Stats.parse(JSON.stringify(source), tr)
  assert.equal(result.ok, true)
  assert.equal(result.activity.calendar.longest, 3)
  assert.equal(result.activity.calendar.streak, 0)
  assert.equal(result.activity.calendar.weeks[0][1].row, 6)
  assert.equal(result.activity.calendar.weeks[0][5].row, 0)

  days[5] = { date: '2026-11-26', contributionCount: 4, contributionLevel: 'FOURTH_QUARTILE' }
  const active = Stats.parse(JSON.stringify(source), tr)
  assert.equal(active.activity.calendar.streak, 1)
  assert.equal(active.activity.calendar.longest, 3)
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
