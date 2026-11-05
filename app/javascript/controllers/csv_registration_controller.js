import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.refreshShortcut()
  }

  disconnect() {
    this.stopHeldEnter()
  }

  stopHeldEnter(event) {
    if (event?.type === "keyup" && event.key !== "Enter") return
    if (event?.type === "visibilitychange" && document.visibilityState !== "hidden") return
    this.enterHeld = false
    clearTimeout(this.enterTimer)
    this.enterTimer = null
  }

  stopOnEditing(event) {
    if (event.target.closest('input, textarea, select, [contenteditable]:not([contenteditable="false"]), [role="textbox"], dialog')) this.stopHeldEnter()
  }

  scheduleHeldEnter() {
    if (!this.enterHeld || this.saving || this.enterTimer || document.visibilityState === "hidden") return
    if (!this.firstRegistrableButton()) return
    this.enterTimer = setTimeout(() => {
      this.enterTimer = null
      if (!this.enterHeld || this.saving) return
      this.registerFirst({ type: "held", preventDefault() {} })
    }, 80)
  }

  firstRegistrableButton() {
    return [...this.element.querySelectorAll('button[name="decision"][value="register"]')][0]
  }

  refreshShortcut() {
    for (const button of this.element.querySelectorAll('button[name="decision"][value="register"]')) {
      const replacement = button.form.querySelector('input[name="allow_replace"]')
      if (button.closest("[data-target-shop]")?.dataset.saving !== "true") button.disabled = !!replacement && !replacement.checked
    }
    const shortcut = this.element.querySelector("[data-csv-shortcut-button]")
    if (!shortcut) return
    const button = this.firstRegistrableButton()
    shortcut.disabled = !!this.saving || !button
    const label = this.element.querySelector("[data-csv-shortcut-name]")
    label.textContent = button?.closest("[data-target-shop]")?.querySelector("h2")?.textContent || "登録できる候補はありません"
  }

  registerFirst(event) {
    if (!this.element.querySelector("[data-csv-shortcut-button]")) return
    if (event.type === "keydown") {
      if (event.key !== "Enter" || event.isComposing || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || event.defaultPrevented) return
      if (event.repeat) {
        if (this.enterHeld) event.preventDefault()
        return
      }
      if (event.target.closest('input, textarea, select, button:not([data-csv-shortcut-button]), a, summary, [contenteditable]:not([contenteditable="false"]), [role="textbox"], dialog')) return
      this.enterHeld = true
    }
    event.preventDefault()
    if (this.saving) return
    const button = this.firstRegistrableButton()
    if (!button) return
    const replacement = button.form.querySelector('input[name="allow_replace"]')
    if (replacement) {
      replacement.checked = true
      button.disabled = false
    }
    if (!button.disabled) button.form.requestSubmit(button)
  }

  async submit(event) {
    const button = event.submitter
    if (!button || button.name !== "decision" || !["register", "undo", "exclude", "restore"].includes(button.value)) return
    event.preventDefault()
    if (this.saving) return
    const form = event.target
    const card = form.closest("[data-target-shop]")
    if (!card || card.dataset.saving === "true") return
    this.saving = true
    card.dataset.saving = "true"
    this.refreshShortcut()
    const data = new FormData(form)
    data.set(button.name, button.value)
    const controls = [...card.querySelectorAll("button, input, select")]
    const disabled = controls.map(control => control.disabled)
    controls.forEach(control => { control.disabled = true })
    const status = this.element.querySelector("[data-csv-registration-status]")
    const notify = message => { status.textContent = message; status.hidden = false }
    let released = false
    const release = () => {
      if (released) return
      released = true
      this.saving = false
      delete card.dataset.saving
      controls.forEach((control, i) => { control.disabled = disabled[i] })
      this.refreshShortcut()
    }
    notify({ register: "登録中…", undo: "取り消し中…", exclude: "候補をすべて外しています…", restore: "未登録に戻しています…" }[button.value])
    try {
      const response = await fetch(form.action, {
        method: "POST", body: data, credentials: "same-origin",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      }).catch(() => { throw new Error("通信に失敗しました。再登録する前に「進捗・結果を更新」で結果を確認してください。") })
      if (!response.headers.get("content-type")?.includes("application/json")) throw new Error("結果を確認できませんでした。再登録する前に「進捗・結果を更新」で確認してください。")
      const result = await response.json()
      if ((!response.ok || !result.success) && !result.remove_from_list) throw new Error(result.message || "処理できませんでした。")
      const y = window.scrollY
      card.remove()
      window.scrollTo({ top: y, behavior: "instant" })
      notify(result.message)
      this.removedShopIds ||= new Set()
      this.removedShopIds.add(card.dataset.targetShop)
      this.revision = (this.revision || 0) + 1
      this.completedSinceRefill = (this.completedSinceRefill || 0) + 1
      this.updateCounts(result.destination === "conflict" ? "conflict" : button.value)
      const sourceGroup = this.element.dataset?.csvRegistrationGroup || "unregistered"
      const destinationGroup = result.destination || { register: "registered", undo: "unregistered", exclude: "excluded", restore: "unregistered" }[button.value]
      const remainingDelta = (destinationGroup === "unregistered" ? 1 : 0) - (sourceGroup === "unregistered" ? 1 : 0)
      for (const selector of ["[data-csv-confidence-remaining-total]", `[data-csv-confidence-remaining="${card.dataset.confidence}"]`]) {
        const counter = this.element.querySelector(selector)
        if (counter) counter.textContent = Math.max(0, Number(counter.textContent.replaceAll(",", "")) + remainingDelta).toLocaleString("en-US")
      }
      release()
      this.scheduleHeldEnter()
      if (this.completedSinceRefill >= 5 || this.element.querySelectorAll("[data-target-shop]").length <= 10) {
        await this.refill()
      }

    } catch (error) {
      this.stopHeldEnter()
      notify(error.message || "通信に失敗しました。再登録する前に結果を確認してください。")
    } finally {
      release()
    }
  }

  updateCounts(decision) {
    const source = this.element.dataset?.csvRegistrationGroup || "unregistered"
    const destination = { register: "registered", undo: "unregistered", exclude: "excluded", restore: "unregistered", conflict: "conflict" }[decision]
    for (const link of this.element.querySelectorAll("[data-csv-group]")) {
      const delta = (link.dataset?.csvGroup === destination ? 1 : 0) - (link.dataset?.csvGroup === source ? 1 : 0)
      if (delta) link.textContent = link.textContent.replace(/（(\d+)店舗）/, (_, count) => `（${Math.max(0, Number(count) + delta)}店舗）`)
    }
  }

  async refill() {
    if (this.refilling) return
    this.refilling = true
    const revision = this.revision
    this.completedSinceRefill = 0
    try {
      const fresh = await fetch(window.location.href, { credentials: "same-origin", headers: { Accept: "text/html" } })
      if (!fresh.ok) throw new Error("refresh failed")
      const html = new DOMParser().parseFromString(await fresh.text(), "text/html")
      if (!html.querySelector('[data-controller="csv-registration"]')) throw new Error("refresh failed")
      const y = window.scrollY
      if (revision === this.revision) {
        for (const selector of ["[data-csv-registration-counts]", "[data-csv-registration-pagination]", "[data-csv-registration-ready]", "[data-csv-confidence-summary]"]) {
          const current = this.element.querySelector(selector)
          const replacement = html.querySelector(selector)
          if (current && replacement) current.replaceWith(replacement)
        }
      }
      for (const candidate of html.querySelectorAll("[data-target-shop]")) {
        const id = candidate.dataset.targetShop
        if (this.removedShopIds?.has(id)) continue
        if (!this.element.querySelector(`[data-target-shop="${id}"]`)) {
          const last = [...this.element.querySelectorAll("[data-target-shop]")].at(-1)
          if (last) last.after(candidate)
          else this.element.querySelector("[data-csv-registration-pagination]").after(candidate)
        }
      }
      window.scrollTo({ top: y, behavior: "instant" })
      this.refreshShortcut()
    } catch {
      const status = this.element.querySelector("[data-csv-registration-status]")
      this.stopHeldEnter()
      status.textContent += " 件数・次の候補の更新に失敗しました。「進捗・結果を更新」で確認できます。"
      status.hidden = false
    } finally {
      this.refilling = false
      this.scheduleHeldEnter()
      if (revision !== this.revision && (this.completedSinceRefill >= 5 || this.element.querySelectorAll("[data-target-shop]").length <= 10)) this.refill()
    }
  }

}
