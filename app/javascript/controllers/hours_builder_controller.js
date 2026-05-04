import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (this.element.dataset.hoursBuilderBound === "1") return
    this.element.dataset.hoursBuilderBound = "1"

    this.openingText =
      this.element.querySelector("#shop_opening_hours_text") ||
      this.element.querySelector("#shop_edit_request_proposed_opening_hours_text")

    this.holidayText =
      this.element.querySelector("#shop_holiday_hours_text") ||
      this.element.querySelector("#shop_edit_request_proposed_holiday_hours_text")

    this.closedText =
      this.element.querySelector("#shop_closed_days_text") ||
      this.element.querySelector("#shop_edit_request_proposed_closed_days_text")

    this.bindEvents()
    this.applyExistingTextToUi()
  }

  bindEvents() {
    this.element.querySelectorAll("input, select").forEach((input) => {
      input.addEventListener("change", () => this.rebuild())
    })

    this.element.querySelectorAll("[data-copy-hours-to-all]").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.preventDefault()
        this.copyHoursToAll(button.closest("[data-hours-row]"))
      })
    })
  }

  rangeText(start, end) {
    if (!start || !end) return ""
    return `${start}-${end}`
  }

  parseRange(text) {
    const match = text.match(/(\d{2}:\d{2})-(\d{2}:\d{2})/)
    if (!match) return ["", ""]
    return [match[1], match[2]]
  }

  setSelect(row, selector, value) {
    const select = row.querySelector(selector)
    if (select && value) select.value = value
  }

  applyExistingTextToUi() {
    const opening = this.openingText?.value || ""
    const holiday = this.holidayText?.value || ""
    const closed = this.closedText?.value || ""

    this.applyClosedDays(closed)
    this.applyOpeningLines(opening)
    this.applyHolidayLine(holiday)
  }

  applyClosedDays(text) {
    const closedLabels = text
      .split(/[・、,\s/]+/)
      .map((s) => s.trim())
      .filter(Boolean)

    this.element.querySelectorAll("[data-hours-row]").forEach((row) => {
      const label = row.querySelector("span")?.textContent?.trim()
      const checkbox = row.querySelector("[data-hours-open]")
      if (!checkbox || !label) return

      checkbox.checked = !(closedLabels.includes(label) || closedLabels.includes(`${label}曜`))
    })
  }

  applyOpeningLines(text) {
    text.split("/").forEach((rawLine) => {
      const line = rawLine.trim()
      if (!line) return

      const label = line.match(/^(月|火|水|木|金|土|日|祝前)\s/)?.[1]
      if (!label) return

      const row = Array.from(this.element.querySelectorAll("[data-hours-row]")).find((candidate) => {
        return candidate.querySelector("span")?.textContent?.trim() === label
      })

      if (!row) return
      this.applyLineToRow(row, line)
    })
  }

  applyHolidayLine(text) {
    const line = text.trim()
    if (!line) return

    const row = Array.from(this.element.querySelectorAll("[data-hours-row]")).find((candidate) => {
      return candidate.querySelector("span")?.textContent?.trim() === "祝日"
    })

    if (!row) return
    this.applyLineToRow(row, line)
  }

  applyLineToRow(row, line) {
    const checkbox = row.querySelector("[data-hours-open]")
    if (checkbox) checkbox.checked = true

    const cleanLine = line.replace(/^月|^火|^水|^木|^金|^土|^日|^祝前/, "").trim()
    const [hoursPart, smokingPart] = cleanLine.split("（喫煙可：")

    const ranges = hoursPart.match(/\d{2}:\d{2}-\d{2}:\d{2}/g) || []

    if (ranges[0]) {
      const [start, end] = this.parseRange(ranges[0])
      this.setSelect(row, "[data-hours-start1]", start)
      this.setSelect(row, "[data-hours-end1]", end)
    }

    if (ranges[1]) {
      const [start, end] = this.parseRange(ranges[1])
      this.setSelect(row, "[data-hours-start2]", start)
      this.setSelect(row, "[data-hours-end2]", end)
    }

    const smokingSame = row.querySelector("[data-smoking-same]")

    if (smokingPart && !smokingPart.includes("営業時間中")) {
      if (smokingSame) smokingSame.checked = false

      const [start, end] = this.parseRange(smokingPart)
      this.setSelect(row, "[data-smoking-start]", start)
      this.setSelect(row, "[data-smoking-end]", end)
    } else if (smokingSame) {
      smokingSame.checked = true
    }
  }

  copyValue(fromRow, toRow, selector) {
    const from = fromRow?.querySelector(selector)
    const to = toRow?.querySelector(selector)
    if (!from || !to) return

    if (from.type === "checkbox") {
      to.checked = from.checked
    } else {
      to.value = from.value
    }
  }

  copyHoursToAll(sourceRow) {
    if (!sourceRow) return

    const selectors = [
      "[data-hours-open]",
      "[data-hours-start1]",
      "[data-hours-end1]",
      "[data-hours-start2]",
      "[data-hours-end2]",
      "[data-smoking-same]",
      "[data-smoking-start]",
      "[data-smoking-end]"
    ]

    this.element.querySelectorAll("[data-hours-row]").forEach((row) => {
      if (row === sourceRow) return

      selectors.forEach((selector) => {
        this.copyValue(sourceRow, row, selector)
      })
    })

    this.rebuild()
  }

  rebuild() {
    const openingLines = []
    const holidayLines = []
    const closedDays = []

    this.element.querySelectorAll("[data-hours-row]").forEach((row) => {
      const label = row.querySelector("span")?.textContent?.trim()
      const open = row.querySelector("[data-hours-open]")?.checked

      if (!open) {
        if (label) closedDays.push(label)
        return
      }

      const start1 = row.querySelector("[data-hours-start1]")?.value
      const end1 = row.querySelector("[data-hours-end1]")?.value
      const start2 = row.querySelector("[data-hours-start2]")?.value
      const end2 = row.querySelector("[data-hours-end2]")?.value

      let hours = [
        this.rangeText(start1, end1),
        this.rangeText(start2, end2)
      ].filter(Boolean).join(", ")

      if (!hours) hours = "営業時間未設定"

      const smokingSame = row.querySelector("[data-smoking-same]")?.checked
      const smokingStart = row.querySelector("[data-smoking-start]")?.value
      const smokingEnd = row.querySelector("[data-smoking-end]")?.value

      let smoking = ""

      if (smokingSame) {
        smoking = "（喫煙可：営業時間中）"
      } else if (smokingStart && smokingEnd) {
        smoking = `（喫煙可：${smokingStart}-${smokingEnd}）`
      }

      const line = `${label} ${hours}${smoking}`

      if (label === "祝日") {
        holidayLines.push(`${hours}${smoking}`)
      } else {
        openingLines.push(line)
      }
    })

    if (this.openingText) {
      this.openingText.value = openingLines.join(" / ")
    }

    if (this.holidayText) {
      this.holidayText.value = holidayLines.join(" / ")
    }

    if (this.closedText) {
      this.closedText.value = closedDays.length ? closedDays.join("・") : "なし"
    }
  }
}