// /Users/kawamuratakuya/dev/suelog/app/javascript/hero_fit.js
function fitText(el, min = 12, max = 48) {
  let size = max
  el.style.fontSize = `${size}px`

  while (el.scrollWidth > el.clientWidth && size > min) {
    size -= 1
    el.style.fontSize = `${size}px`
  }
}

function applyFit() {
  const title = document.querySelector(".hero-title")
  const sub = document.querySelector(".hero-sub")

  if (title) fitText(title, 18, 48)
  if (sub) fitText(sub, 12, 20)
}

window.addEventListener("load", applyFit)
window.addEventListener("resize", applyFit)
document.addEventListener("turbo:load", applyFit)