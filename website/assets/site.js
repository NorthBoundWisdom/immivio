(() => {
  "use strict";
  const zh = document.documentElement.lang.startsWith("zh");
  const theme = document.querySelector("[data-theme-toggle]");
  try {
    const saved = localStorage.getItem("immivio-theme");
    if (saved === "light" || saved === "dark")
      document.body.dataset.theme = saved;
  } catch (_) {}
  function reflectTheme() {
    if (theme)
      theme.setAttribute(
        "aria-pressed",
        String(document.body.dataset.theme === "light"),
      );
  }
  reflectTheme();
  theme?.addEventListener("click", () => {
    document.body.dataset.theme =
      document.body.dataset.theme === "light" ? "dark" : "light";
    try {
      localStorage.setItem("immivio-theme", document.body.dataset.theme);
    } catch (_) {}
    reflectTheme();
  });
  const dialog = document.querySelector(".lightbox");
  if (dialog && typeof dialog.showModal === "function") {
    document.querySelectorAll("[data-screenshot]").forEach((link) =>
      link.addEventListener("click", (event) => {
        event.preventDefault();
        const image = dialog.querySelector("img");
        image.src = link.href;
        image.alt = link.querySelector("img")?.alt || "";
        dialog.querySelector("p").textContent = image.alt;
        dialog.querySelector("a").href = link.href;
        dialog.showModal();
      }),
    );
    dialog
      .querySelector("button")
      .addEventListener("click", () => dialog.close());
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) {
        const r = dialog.getBoundingClientRect();
        if (
          event.clientX < r.left ||
          event.clientX > r.right ||
          event.clientY < r.top ||
          event.clientY > r.bottom
        )
          dialog.close();
      }
    });
  }
  const form = document.querySelector("#download-picker");
  if (!form) return;
  const link = document.querySelector("#download-link"),
    meta = document.querySelector("#download-meta");
  const builds =
    "https://github.com/NorthBoundWisdom/immivio/actions/workflows/android-release.yml";
  let release = null;
  function renderDownload() {
    const platform = form.querySelector("select").value;
    const pattern = new RegExp(
      "^Immivio-" + platform + "-[0-9][A-Za-z0-9._-]*-release-[0-9]{8}\\.apk$",
      "i",
    );
    const asset = release?.assets?.find(
      (item) =>
        pattern.test(item.name) &&
        /^https:\/\/github\.com\/NorthBoundWisdom\/immivio\/releases\/download\//.test(
          item.browser_download_url || "",
        ),
    );
    link.href = asset ? asset.browser_download_url : builds;
    link.textContent = asset
      ? (zh ? "下载 " : "Download ") + platform + " APK ↗"
      : zh
        ? "获取开发版构建 ↗"
        : "Get a development build ↗";
    meta.textContent = asset
      ? release.tag_name +
        " · " +
        Math.round(asset.size / 1048576) +
        " MB · APK"
      : zh
        ? "选择成功运行的 Artifacts，下载 Immivio-" +
          platform +
          " 安装包。需要登录 GitHub。"
        : "Choose Artifacts in a successful run, then the Immivio-" +
          platform +
          " package. GitHub sign-in is required.";
  }
  form.addEventListener("change", renderDownload);
  renderDownload();
  const local = document
    .querySelector("script[data-site-script]")
    .src.replace(/site\.js$/, "releases.json");
  fetch(local)
    .then((response) => (response.ok ? response.json() : Promise.reject()))
    .then((data) => {
      release = data;
      renderDownload();
    })
    .catch(() => {});
})();
