import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
const source = fs.readFileSync('app/javascript/controllers/article_table_controller.js', 'utf8').replace(/^import .*$/gm, '')
const { parseTSV, tableHTML, renderCell } = await import(`data:text/javascript;base64,${Buffer.from('class Controller {}\n' + source).toString('base64')}`)

test('Excel tabs preserve empty cells, multiline cells, quotes and CRLF', () => {
  assert.deepEqual(parseTSV('店名\t料金\t備考\r\nA\t\t"改行\nと""引用"""\r\n'), [['店名', '料金', '備考'], ['A', '', '改行\nと"引用"']])
})
test('table cell contents cannot introduce markup or shortcodes as HTML', () => {
  const html = tableHTML([['<script>alert(1)</script>', '&"'], ['改行\nセル', '']], true)
  assert.ok(html.includes('<th>&lt;script&gt;alert(1)&lt;/script&gt;</th>'))
  assert.ok(html.includes('<td>改行<br>セル</td>'))
  assert.ok(!html.includes('<script>'))
  assert.ok(!tableHTML([['見出しなし']], false).includes('<th>'))
})

test('external links support labels and escaped text without unsafe schemes', () => {
  assert.equal(renderCell('[公式サイト](https://example.com/?a=1&b=2)'), '<a href="https://example.com/?a=1&amp;b=2" target="_blank" rel="noopener noreferrer">公式サイト</a>')
  assert.ok(renderCell('https://example.com/').includes('href="https://example.com/"'))
  assert.ok(!renderCell('[危険](javascript:alert(1))').includes('<a'))
  assert.ok(!renderCell('https://').includes('<a'))
  assert.ok(renderCell('[<img onerror=x>](https://example.com/)').includes('&lt;img onerror=x&gt;'))
  assert.ok(renderCell('[公式\\[店\\]](https://example.com/)').includes('>公式[店]</a>'))
})
