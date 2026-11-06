(() => {
  "use strict";
  const root = document.documentElement;
  const zh = root.lang.startsWith("zh");

  // Theme: an explicit choice is kept in localStorage ("immivio-theme");
  // otherwise the page follows the system preference.
  const toggle = document.querySelector("[data-theme-toggle]");
  const systemLight = () =>
    window.matchMedia("(prefers-color-scheme: light)").matches;
  const isLight = () =>
    root.dataset.theme ? root.dataset.theme === "light" : systemLight();
  const reflect = () =>
    toggle?.setAttribute("aria-pressed", String(isLight()));
  reflect();
  toggle?.addEventListener("click", () => {
    root.dataset.theme = isLight() ? "dark" : "light";
    try {
      localStorage.setItem("immivio-theme", root.dataset.theme);
    } catch (_) {}
    reflect();
  });

  // Header border once the page scrolls.
  const header = document.querySelector(".site-header");
  const onScroll = () =>
    header?.classList.toggle("scrolled", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  // Reveal sections as they enter the viewport.
  const revealed = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) =>
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("in");
            observer.unobserve(entry.target);
          }
        }),
      { rootMargin: "0px 0px -8% 0px" },
    );
    revealed.forEach((node) => observer.observe(node));
  } else revealed.forEach((node) => node.classList.add("in"));

  // Highlight the current section in a page's table of contents.
  const tocLinks = [...document.querySelectorAll(".toc a[href^='#']")];
  if (tocLinks.length && "IntersectionObserver" in window) {
    const byId = new Map(tocLinks.map((a) => [a.hash.slice(1), a]));
    const spy = new IntersectionObserver(
      (entries) =>
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          tocLinks.forEach((a) => a.classList.remove("active"));
          byId.get(entry.target.id)?.classList.add("active");
        }),
      { rootMargin: "-30% 0px -60% 0px" },
    );
    byId.forEach((_, id) => {
      const target = document.getElementById(id);
      if (target) spy.observe(target);
    });
  }

  // Screenshot lightbox.
  const dialog = document.querySelector(".lightbox");
  if (dialog && typeof dialog.showModal === "function") {
    const image = dialog.querySelector("img");
    document.querySelectorAll("[data-screenshot]").forEach((link) =>
      link.addEventListener("click", (event) => {
        event.preventDefault();
        const thumb = link.querySelector("img");
        image.src = link.href;
        image.alt = thumb?.alt || "";
        dialog.querySelector("p").textContent = image.alt;
        dialog.querySelector("a").href = link.href;
        dialog.showModal();
      }),
    );
    dialog
      .querySelector("button")
      .addEventListener("click", () => dialog.close());
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) dialog.close();
    });
  }

  // Download picker: offer the matching APK from the latest complete release,
  // or fall back to development builds.
  const form = document.querySelector("#download-picker");
  if (!form) return;
  const link = document.querySelector("#download-link");
  const meta = document.querySelector("#download-meta");
  const builds =
    "https://github.com/NorthBoundWisdom/immivio/actions/workflows/android-release.yml";
  const names = { QUEST: "Meta Quest", PICO: "PICO", OpenXR: "OpenXR" };
  let release = null;
  function render() {
    const platform = form.querySelector("input:checked")?.value || "PICO";
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
    link.querySelector("span").textContent = asset
      ? (zh ? "下载 " : "Download for ") + names[platform]
      : zh
        ? "获取开发版构建"
        : "Get a development build";
    meta.textContent = asset
      ? release.tag_name +
        " · " +
        Math.round(asset.size / 1048576) +
        " MB · APK"
      : zh
        ? "在成功运行的构建中打开 Artifacts，下载 Immivio-" +
          platform +
          " 安装包（需要登录 GitHub）。"
        : "Open Artifacts in a successful run and download the Immivio-" +
          platform +
          " package (GitHub sign-in required).";
  }
  form.addEventListener("change", render);
  render();
  const local = document
    .querySelector("script[data-site-script]")
    .src.replace(/site\.js$/, "releases.json");
  fetch(local)
    .then((response) => (response.ok ? response.json() : Promise.reject()))
    .then((data) => {
      release = data;
      render();
    })
    .catch(() => {});
})();
