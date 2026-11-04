import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async submit(event) {
    const button = event.submitter
    if (!button || button.name !== "decision" || !["register", "undo"].includes(button.value)) return
    event.preventDefault()
    if (this.saving) return
    const form = event.target
    const card = form.closest("[data-target-shop]")
    if (!card || card.dataset.saving === "true") return
    this.saving = true
    card.dataset.saving = "true"
    const data = new FormData(form)
    data.set(button.name, button.value)
    const controls = [...card.querySelectorAll("button, input, select")]
    const disabled = controls.map(control => control.disabled)
    controls.forEach(control => { control.disabled = true })
    const status = this.element.querySelector("[data-csv-registration-status]")
    const notify = message => { status.textContent = message; status.hidden = false }
    notify(button.value === "register" ? "登録中…" : "取り消し中…")
    try {
      const response = await fetch(form.action, {
        method: "POST", body: data, credentials: "same-origin",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      }).catch(() => { throw new Error("通信に失敗しました。再登録する前に「進捗・結果を更新」で結果を確認してください。") })
      if (!response.headers.get("content-type")?.includes("application/json")) throw new Error("結果を確認できませんでした。再登録する前に「進捗・結果を更新」で確認してください。")
      const result = await response.json()
      if (!response.ok || !result.success) throw new Error(result.message || "処理できませんでした。")
      const y = window.scrollY
      card.remove()
      window.scrollTo({ top: y, behavior: "instant" })
      notify(result.message)
      // Refresh counts and append the next candidates without replacing forms being edited.
      try {
        const fresh = await fetch(window.location.href, { credentials: "same-origin", headers: { Accept: "text/html" } })
        if (!fresh.ok) throw new Error("refresh failed")
        const html = new DOMParser().parseFromString(await fresh.text(), "text/html")
        if (!html.querySelector('[data-controller="csv-registration"]')) throw new Error("refresh failed")
        for (const selector of ["[data-csv-registration-counts]", "[data-csv-registration-pagination]", "[data-csv-registration-ready]"]) {
          const current = this.element.querySelector(selector)
          const replacement = html.querySelector(selector)
          if (current && replacement) current.replaceWith(replacement)
        }
        for (const candidate of html.querySelectorAll("[data-target-shop]")) {
          const id = candidate.dataset.targetShop
          if (!this.element.querySelector(`[data-target-shop="${id}"]`)) {
            const last = [...this.element.querySelectorAll("[data-target-shop]")].at(-1)
            if (last) last.after(candidate)
            else this.element.querySelector("[data-csv-registration-pagination]").after(candidate)
          }
        }
        window.scrollTo({ top: y, behavior: "instant" })
      } catch {
        notify(`${result.message} 件数・次の候補の更新に失敗しました。「進捗・結果を更新」で確認できます。`)
      }
    } catch (error) {
      notify(error.message || "通信に失敗しました。再登録する前に結果を確認してください。")
    } finally {
      this.saving = false
      delete card.dataset.saving
      controls.forEach((control, i) => { control.disabled = disabled[i] })
    }
  }
}
