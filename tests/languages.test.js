const assert = require('node:assert/strict')
const test = require('node:test')
const Languages = require('../GithubLanguages.js')

const tr = key => key

test('the query and jq projection are bounded and keep language fields', () => {
  const query = Languages.query()
  assert.equal((query.match(/{/g) || []).length, (query.match(/}/g) || []).length)
  assert.match(query, /repositories\(first: 100, ownerAffiliations: OWNER/)
  assert.match(query, /languages\(first: 10, orderBy: \{field: SIZE/)
  assert.match(query, /name color/)

  const argv = Languages.command()
  assert.deepEqual(argv.slice(0, 4), ['gh', 'api', 'graphql', '-f'])
  assert.equal(argv[4], `query=${query}`)
  assert.equal(argv[5], '--jq')
  assert.match(argv[6], /group_by\(\.name\)/)
  assert.match(argv[6], /sort_by\(-\.bytes\)/)
  assert.match(argv[6], /\(\.errors \/\/ \[\]\) \| length/)
})

test('bytes aggregate by language and drive descending percentages', () => {
  const source = JSON.stringify([
    { name: 'Rust', color: '#dea584', bytes: 600 },
    { name: 'QML', color: '#44a51c', bytes: 300 },
    { name: 'Rust', color: '#dea584', bytes: 100 }
  ])
  const result = Languages.parse(source, tr)
  assert.equal(result.ok, true)
  assert.equal(result.total, 1000)
  assert.deepEqual(result.languages.map(row => row.name), ['Rust', 'QML'])
  assert.deepEqual(result.languages.map(row => row.percent), [70, 30])
  assert.equal(result.languages[0].bytes, 700)
  assert.equal(result.languages[0].color, '#dea584')
})

test('more than eight languages keep the total honest with Other', () => {
  const source = JSON.stringify(Array.from({ length: 12 }, (_, i) => ({
    name: `Lang${String(i).padStart(2, '0')}`,
    color: '#123456',
    bytes: 12 - i
  })))
  const result = Languages.parse(source, tr)
  assert.equal(result.ok, true)
  assert.equal(result.languages.length, Languages.MAX_SHOWN + 1)
  assert.equal(result.languages.at(-1).name, 'Other')
  const sum = result.languages.reduce((total, row) => total + row.bytes, 0)
  assert.equal(sum, result.total)
})

test('invalid, oversized and malformed payloads fail closed', () => {
  const cases = [
    '',
    'not json',
    '{}',
    JSON.stringify([{ name: '', color: '#123456', bytes: 10 }]),
    JSON.stringify([{ name: 'Rust', color: 'red', bytes: 10 }]),
    JSON.stringify([{ name: 'Rust', color: '#123456', bytes: -1 }]),
    JSON.stringify([{ name: 'Rust', color: '#123456', bytes: 'many' }]),
    JSON.stringify(Array.from({ length: 33 }, () => ({ name: 'Rust', color: '#123456', bytes: 1 }))),
    'x'.repeat(Languages.MAX_OUTPUT + 1)
  ]
  for (const source of cases) {
    const result = Languages.parse(source, tr)
    assert.equal(result.ok, false, source.slice(0, 40))
    assert.deepEqual(result.languages, [])
    assert.equal(result.total, 0)
    assert.match(result.error, /GitHub languages are unavailable/)
  }
})

test('a null GitHub color stays usable without inventing a hex value', () => {
  const result = Languages.parse(JSON.stringify([{ name: 'Unknown', color: null, bytes: 5 }]), tr)
  assert.equal(result.ok, true)
  assert.equal(result.languages[0].color, '')
})
