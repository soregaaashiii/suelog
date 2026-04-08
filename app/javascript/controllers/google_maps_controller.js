import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    apiKey: String,

    // /map 用
    shops: Array,

    // show 用
    mode: { type: String, default: "list" }, // "list" or "single"
    centerLat: Number,
    centerLng: Number,
    centerName: String,
    centerId: String,
  }

  connect() {
    this.map = null
    this.markers = []
    this.meMarker = null

    this.element.style.minHeight = this.element.style.minHeight || "300px"

    this.loadGoogleMaps()
      .then(() => this.initMap())
      .catch((e) => console.error("[google-maps] load failed:", e))
  }

  async loadGoogleMaps() {
    if (window.google?.maps) return

    const key = (this.apiKeyValue || "").trim()
    if (!key) throw new Error("GOOGLE_MAPS_API_KEY is empty")

    if (window.__gmapsLoadingPromise) {
      await window.__gmapsLoadingPromise
      return
    }

    window.__gmapsLoadingPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}`
      script.async = true
      script.defer = true
      script.onload = () => resolve()
      script.onerror = () => reject(new Error("failed to load google maps script"))
      document.head.appendChild(script)
    })

    await window.__gmapsLoadingPromise
  }

  initMap() {
    this.map = new google.maps.Map(this.element, {
      center: { lat: 34.702485, lng: 135.495951 },
      zoom: 13,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
    })

    if (this.modeValue === "single") {
      this.initSingle()
    } else {
      this.initList()
    }

    setTimeout(() => {
      if (!this.map) return
      google.maps.event.trigger(this.map, "resize")
    }, 50)
  }

  initList() {
    const shops = Array.isArray(this.shopsValue) ? this.shopsValue : []
    const bounds = new google.maps.LatLngBounds()

    shops.forEach((s) => {
      if (s.lat == null || s.lng == null) return

      const pos = { lat: Number(s.lat), lng: Number(s.lng) }
      const marker = new google.maps.Marker({
        map: this.map,
        position: pos,
        title: s.name || "",
      })

      const safeName = this.escapeHtml(s.name || "")
      const shopUrl = `/shops/${encodeURIComponent(s.id)}`

      const info = new google.maps.InfoWindow({
        content: `
          <div style="min-width:160px;">
            <div style="font-weight:700; margin-bottom:6px;">${safeName}</div>
            <a href="${shopUrl}" target="_blank" rel="noopener">詳細を開く</a>
          </div>
        `,
      })

      marker.addListener("click", () => info.open({ anchor: marker, map: this.map }))

      this.markers.push(marker)
      bounds.extend(pos)
    })

    if (this.markers.length > 0) {
      this.map.fitBounds(bounds, 60)
      setTimeout(() => this.map.fitBounds(bounds, 60), 80)
    }
  }

  initSingle() {
    const lat = Number(this.centerLatValue)
    const lng = Number(this.centerLngValue)

    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      console.warn("[google-maps] shop lat/lng missing")
      this.map.setCenter({ lat: 34.702485, lng: 135.495951 })
      this.map.setZoom(13)

      const div = document.createElement("div")
      div.style.padding = "10px"
      div.style.color = "#666"
      div.style.fontSize = "12px"
      div.textContent = "この店舗は位置情報（緯度・経度）が未設定のため、地図ピンを表示できません。"
      this.element.appendChild(div)
      return
    }

    const pos = { lat, lng }
    this.map.setCenter(pos)
    this.map.setZoom(16)

    const marker = new google.maps.Marker({
      map: this.map,
      position: pos,
      title: this.centerNameValue || "",
    })

    const safeName = this.escapeHtml(this.centerNameValue || "")
    const shopUrl = `/shops/${encodeURIComponent(this.centerIdValue || "")}`

    const info = new google.maps.InfoWindow({
      content: `
        <div style="min-width:160px;">
          <div style="font-weight:700; margin-bottom:6px;">${safeName}</div>
          <a href="${shopUrl}" target="_blank" rel="noopener">詳細を開く</a>
        </div>
      `,
    })

    info.open({ anchor: marker, map: this.map })
    marker.addListener("click", () => info.open({ anchor: marker, map: this.map }))
  }

  locate() {
    if (!navigator.geolocation) {
      alert("このブラウザでは位置情報が使えません。")
      return
    }

    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const me = { lat: pos.coords.latitude, lng: pos.coords.longitude }

        if (this.meMarker) this.meMarker.setMap(null)

        this.meMarker = new google.maps.Marker({
          map: this.map,
          position: me,
          title: "現在地",
        })

        this.map.setCenter(me)
        this.map.setZoom(15)
      },
      () => {
        alert("位置情報が取得できませんでした（許可しているか確認してください）")
      },
      { enableHighAccuracy: true, timeout: 8000 }
    )
  }

  escapeHtml(str) {
    return String(str)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }
}