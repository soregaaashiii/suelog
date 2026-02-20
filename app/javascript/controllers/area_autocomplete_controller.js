// app/javascript/controllers/area_autocomplete_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
static targets = ["input", "list", "hidden"]
static values = { items: Array }

connect() {
this.open = false
this.highlightIndex = -1
this.filtered = []
this.ensureList()

// 外側クリックで閉じる
this._onDocClick = (e) => {
if (!this.element.contains(e.target)) this.closeList()
}
document.addEventListener("click", this._onDocClick)
}

disconnect() {
document.removeEventListener("click", this._onDocClick)
}

ensureList() {
if (!this.hasListTarget) return
this.listTarget.setAttribute("role", "listbox")
this.listTarget.style.display = "none"
}

// ★ 入力イベント（従来どおり絞り込み）
onInput() {
const q = (this.inputTarget.value || "").trim()
this.filtered = this.filterItems(q)
this.renderList()
if (this.filtered.length > 0) this.openList()
else this.closeList()
}

// ★ フォーカスしたら、空でも候補を出す（ジャンル風）
onFocus() {
const q = (this.inputTarget.value || "").trim()
this.filtered = this.filterItems(q, { allowEmpty: true })
this.renderList()
if (this.filtered.length > 0) this.openList()
}

// ★ クリックでも開きたい場合（スマホ対策にもなる）
onClick() {
if (this.open) return
this.onFocus()
}

onKeydown(e) {
if (!this.open) return

if (e.key === "ArrowDown") {
e.preventDefault()
this.highlightIndex = Math.min(this.highlightIndex + 1, this.filtered.length - 1)
this.updateHighlight()
} else if (e.key === "ArrowUp") {
e.preventDefault()
this.highlightIndex = Math.max(this.highlightIndex - 1, 0)
this.updateHighlight()
} else if (e.key === "Enter") {
if (this.highlightIndex >= 0 && this.filtered[this.highlightIndex]) {
e.preventDefault()
this.select(this.filtered[this.highlightIndex])
}
} else if (e.key === "Escape") {
e.preventDefault()
this.closeList()
}
}

filterItems(q, opts = {}) {
const items = this.itemsValue || []
const allowEmpty = !!opts.allowEmpty

// ★ 空なら「上から候補を出す」
if (q === "") return allowEmpty ? items.slice(0, 12) : []

const lower = q.toLowerCase()
const starts = []
const contains = []

for (const it of items) {
const s = String(it)
const sl = s.toLowerCase()
if (sl.startsWith(lower)) starts.push(s)
else if (sl.includes(lower)) contains.push(s)
}

return [...starts, ...contains].slice(0, 12)
}

renderList() {
this.listTarget.innerHTML = ""
this.highlightIndex = -1

this.filtered.forEach((name, idx) => {
const btn = document.createElement("button")
btn.type = "button"
btn.className = "area-ac__item"
btn.setAttribute("role", "option")
btn.dataset.index = String(idx)
btn.textContent = name

btn.addEventListener("mousedown", (e) => {
e.preventDefault()
this.select(name)
})

this.listTarget.appendChild(btn)
})
}

updateHighlight() {
const items = this.listTarget.querySelectorAll(".area-ac__item")
items.forEach((el, i) => {
if (i === this.highlightIndex) el.classList.add("is-active")
else el.classList.remove("is-active")
})
}

select(name) {
this.inputTarget.value = name
if (this.hasHiddenTarget) this.hiddenTarget.value = name
this.closeList()
}

openList() {
this.open = true
this.listTarget.style.display = "block"
}

closeList() {
this.open = false
this.listTarget.style.display = "none"
}
}