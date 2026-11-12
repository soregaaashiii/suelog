import { Controller } from "@hotwired/stimulus"
import "trix"

// Tables are content attachments so Trix retains their structure on save/reopen.
export default class extends Controller {
  static targets = ["dialog", "grid", "header", "rows", "columns", "message"]

  get editor() { return this.element.querySelector("trix-editor").editor }

  open() {
    this.range = this.editor.getSelectedRange()
    this.attachment = this.editor.getDocument().getAttachments().find(attachment => {
      const range = this.editor.getDocument().getRangeOfAttachment(attachment)
      return attachment.getContent()?.includes('class="article-table"') && range && this.range[0] >= range[0] && this.range[0] <= range[1]
    })
    const content = this.attachment?.getContent()
    const table = content ? new DOMParser().parseFromString(content, "text/html").querySelector("table") : null
    this.headerTarget.checked = table ? !!table.querySelector("th") : true
    this.draw(table ? this.readTable(table) : Array.from({ length: 3 }, () => Array(3).fill("")))
    this.dialogTarget.showModal()
    this.gridTarget.querySelector("textarea")?.focus()
  }

  close() { this.dialogTarget.close() }

  readTable(table) {
    if (table.querySelector("[rowspan]:not([rowspan='1']), [colspan]:not([colspan='1'])")) {
      throw new Error("結合セルには対応していません。Excelでセルの結合を解除してから貼り付けてください。")
    }
    return Array.from(table.rows, row => Array.from(row.cells, cell => {
      const copy = cell.cloneNode(true)
      copy.querySelectorAll("br").forEach(br => br.replaceWith("\n"))
      return copy.textContent
    }))
  }

  values() {
    return Array.from(this.gridTarget.querySelectorAll("tr"), row => Array.from(row.querySelectorAll("textarea"), input => input.value))
  }

  draw(values) {
    const columns = Math.max(1, ...values.map(row => row.length))
    if (values.length > 100 || columns > 20) throw new Error("表は100行・20列以内にしてください。")
    this.messageTarget.textContent = ""
    this.gridTarget.replaceChildren()
    values.forEach((row, rowIndex) => {
      const tr = document.createElement("tr")
      for (let column = 0; column < columns; column++) {
        const td = document.createElement("td")
        const input = document.createElement("textarea")
        input.rows = 2
        input.value = row[column] || ""
        input.setAttribute("aria-label", `${rowIndex + 1}行${column + 1}列`)
        input.dataset.row = rowIndex
        input.dataset.column = column
        td.append(input)
        tr.append(td)
      }
      this.gridTarget.append(tr)
    })
    this.rowsTarget.value = values.length
    this.columnsTarget.value = columns
  }

  resize() {
    const rows = Number(this.rowsTarget.value), columns = Number(this.columnsTarget.value)
    if (!Number.isInteger(rows) || rows < 1 || rows > 100 || !Number.isInteger(columns) || columns < 1 || columns > 20) {
      this.messageTarget.textContent = "行数は1〜100、列数は1〜20で指定してください。"
      return
    }
    const old = this.values()
    if ((rows < old.length || columns < old[0].length) && !window.confirm("はみ出すセルの内容を削除しますか？")) return
    this.draw(Array.from({ length: rows }, (_, r) => Array.from({ length: columns }, (_, c) => old[r]?.[c] || "")))
  }

  paste(event) {
    const html = event.clipboardData?.getData("text/html") || ""
    const text = event.clipboardData?.getData("text/plain") || ""
    const table = html ? new DOMParser().parseFromString(html, "text/html").querySelector("table") : null
    if (!table && !text.includes("\t")) return
    event.preventDefault()
    event.stopImmediatePropagation()
    try {
      const incoming = table ? this.readTable(table) : parseTSV(text)
      if (event.target.closest("trix-editor")) {
        this.range = this.editor.getSelectedRange()
        this.attachment = null
        this.headerTarget.checked = true
        this.draw(incoming)
        this.dialogTarget.showModal()
      } else {
        const row = Number(event.target.dataset.row || 0), column = Number(event.target.dataset.column || 0)
        const old = this.values()
        const rows = Math.max(old.length, row + incoming.length)
        const columns = Math.max(old[0].length, column + Math.max(...incoming.map(r => r.length)))
        const merged = Array.from({ length: rows }, (_, r) => Array.from({ length: columns }, (_, c) => old[r]?.[c] || ""))
        incoming.forEach((cells, r) => cells.forEach((value, c) => { merged[row + r][column + c] = value }))
        this.draw(merged)
      }
    } catch (error) {
      if (!this.dialogTarget.open) {
        this.range = this.editor.getSelectedRange()
        this.attachment = null
        this.draw(Array.from({ length: 3 }, () => Array(3).fill("")))
        this.dialogTarget.showModal()
      }
      this.messageTarget.textContent = error.message
    }
  }

  save() {
    const content = tableHTML(this.values(), this.headerTarget.checked)
    if (this.attachment) this.attachment.setAttributes({ content })
    else {
      this.editor.setSelectedRange(this.range)
      this.editor.insertAttachment(new window.Trix.Attachment({ content, contentType: "text/html" }))
      this.editor.insertString("\n")
    }
    this.close()
    this.element.querySelector("trix-editor").focus()
  }
}

export function tableHTML(rows, header) {
  const escape = value => String(value).replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char])).replace(/\r?\n/g, "<br>")
  return `<div class="article-table"><table><tbody>${rows.map((row, index) => `<tr>${row.map(value => { const tag = header && index === 0 ? "th" : "td"; return `<${tag}>${escape(value)}</${tag}>` }).join("")}</tr>`).join("")}</tbody></table></div>`
}

// Excel quotes multiline cells and embedded quotes in its plain-text format.
export function parseTSV(text) {
  const rows = [[]]
  let cell = "", quoted = false
  const input = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  for (let i = 0; i < input.length; i++) {
    const char = input[i]
    if (char === '"' && (quoted || cell === "")) {
      if (quoted && input[i + 1] === '"') { cell += '"'; i++ }
      else quoted = !quoted
    } else if (!quoted && (char === "\t" || char === "\n")) {
      rows[rows.length - 1].push(cell); cell = ""
      if (char === "\n") rows.push([])
    } else cell += char
  }
  rows[rows.length - 1].push(cell)
  if (input.endsWith("\n") && rows.at(-1).length === 1 && rows.at(-1)[0] === "") rows.pop()
  return rows
}
