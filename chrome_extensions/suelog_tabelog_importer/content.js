(() => {
  if (!/^\/[a-z0-9_-]+\/A[0-9]+\/A[0-9]+\/[0-9]+(?:\/|$)/.test(location.pathname)) return;
  if (document.getElementById("suelog-import-button")) return;

  // The tab URL, not a link found in the selected article, identifies the source.
  document.addEventListener("copy", (event) => {
    const target = event.target;
    if (target?.closest?.('input, textarea, [contenteditable="true"]')) return;
    const selection = window.getSelection();
    const text = selection?.toString();
    if (!text || !event.clipboardData) return;
    const container = document.createElement("div");
    for (let index = 0; index < selection.rangeCount; index++) container.append(selection.getRangeAt(index).cloneContents());
    event.clipboardData.setData("text/plain", `${text}\n\n食べログURL\n${location.href}`);
    event.clipboardData.setData("text/html", container.innerHTML);
    event.preventDefault();
  });

  const button = document.createElement("button");
  button.id = "suelog-import-button";
  button.textContent = "吸えログへ送る";

  Object.assign(button.style, {
    position: "fixed",
    right: "20px",
    bottom: "20px",
    zIndex: "999999",
    padding: "12px 18px",
    borderRadius: "999px",
    border: "none",
    background: "#111",
    color: "#fff",
    fontSize: "14px",
    fontWeight: "bold",
    cursor: "pointer",
    boxShadow: "0 2px 8px rgba(0,0,0,0.25)"
  });

  const sendToSuelog = () => {
    if (button.disabled) return;

    button.disabled = true;
    button.textContent = "送信中...";

    const rawText = document.body.innerText;

    const form = document.createElement("form");
    form.method = "POST";
    form.action = "https://suelog.jp/panel_8m4k/shop_import/preview";
    form.target = "_blank";

    const rawInput = document.createElement("textarea");
    rawInput.name = "raw_text";
    rawInput.value = rawText;
    form.appendChild(rawInput);

    const sourceUrlInput = document.createElement("input");
    sourceUrlInput.type = "hidden";
    sourceUrlInput.name = "source_url";
    sourceUrlInput.value = location.href;
    form.appendChild(sourceUrlInput);

    form.style.display = "none";

    document.body.appendChild(form);
    form.submit();
    form.remove();

    setTimeout(() => {
      button.disabled = false;
      button.textContent = "吸えログへ送る";
    }, 1000);
  };

  button.addEventListener("click", sendToSuelog);

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    if (event.isComposing) return;
    if (event.repeat) return;

    const tagName = event.target?.tagName?.toLowerCase();
    if (["input", "textarea", "select", "button"].includes(tagName)) return;

    event.preventDefault();
    sendToSuelog();
  });

  document.body.appendChild(button);
})();