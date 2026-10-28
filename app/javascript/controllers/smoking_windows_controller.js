import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mode", "text", "day", "start", "finish", "message"]

  add() {
    const start = this.startTarget.value
    const finish = this.finishTarget.value
    if (!start || !finish || start === finish) {
      this.messageTarget.textContent = "開始・終了時刻を指定してください。同じ時刻は指定できません。"
      return
    }
    const day = this.dayTarget.value
    const rows = this.textTarget.value.split(/\n/).map(line => line.trim()).filter(Boolean)
    const weekday = /^(?:[月火水木金土日]|祝日|祝前|祝後)\s/
    if (rows.length && (day ? rows.some(line => !weekday.test(line)) : rows.some(line => weekday.test(line)))) {
      this.messageTarget.textContent = "毎日同じ設定と曜日別設定は混在できません。上の欄を曜日別に揃えるか、空にしてから追加してください。"
      return
    }
    const prefix = day ? `${day} ` : ""
    const index = day ? rows.findIndex(line => line.startsWith(prefix)) : (rows.length ? 0 : -1)
    const range = `${start}-${finish}`
    if (index < 0) {
      rows.push(prefix + range)
    } else {
      const body = rows[index].slice(prefix.length)
      if (/喫煙不可|終日禁煙|時間未設定/.test(body)) {
        this.messageTarget.textContent = "この日は禁煙または時間未設定です。上の欄の指定を変更してから追加してください。"
        return
      }
      if (!body.split(/[,、]/).map(value => value.trim()).includes(range)) rows[index] += `, ${range}`
    }
    this.textTarget.value = rows.join("\n")
    this.modeTarget.value = "custom"
    this.textTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.messageTarget.textContent = "時間帯を追加しました。保存すると反映されます。"
  }
}
