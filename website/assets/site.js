(() => {
  'use strict';
  const zh = document.documentElement.lang.startsWith('zh');
  const theme = document.querySelector('[data-theme-toggle]');
  try { const saved = localStorage.getItem('thru3d-theme'); if (saved === 'light' || saved === 'dark') document.body.dataset.theme = saved; } catch (_) {}
  function reflectTheme() { if (theme) theme.setAttribute('aria-pressed', String(document.body.dataset.theme === 'light')); }
  reflectTheme();
  theme?.addEventListener('click', () => {
    document.body.dataset.theme = document.body.dataset.theme === 'light' ? 'dark' : 'light';
    try { localStorage.setItem('thru3d-theme', document.body.dataset.theme); } catch (_) {}
    reflectTheme();
  });
  const dialog = document.querySelector('.lightbox');
  if (dialog && typeof dialog.showModal === 'function') {
    document.querySelectorAll('[data-screenshot]').forEach(link => link.addEventListener('click', event => {
      event.preventDefault();
      const image = dialog.querySelector('img'); image.src = link.href; image.alt = link.querySelector('img')?.alt || '';
      dialog.querySelector('p').textContent = image.alt;
      dialog.querySelector('a').href = link.href;
      dialog.showModal();
    }));
    dialog.querySelector('button').addEventListener('click', () => dialog.close());
    dialog.addEventListener('click', event => { if (event.target === dialog) { const r = dialog.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) dialog.close(); } });
  }
  const form = document.querySelector('#download-picker');
  if (!form) return;
  const link = document.querySelector('#download-link'), meta = document.querySelector('#download-meta'), help = document.querySelector('#edition-help');
  const releases = 'https://github.com/NorthBoundWisdom/Thru3D-Media-Player/releases/latest';
  let release = null;
  function renderDownload() {
    const platform = form.querySelector('select').value;
    const edition = form.querySelector('input:checked').value;
    const experimental = platform === 'OpenXR';
    help.textContent = (edition === 'noai' ? (zh ? '普通视频、照片与已有立体媒体；安装体积更小，不含实时 AI 转换。' : 'Ordinary videos, photos and existing stereo media. A smaller install without live AI conversion.') : (zh ? '增加支持内容的深度和人物抠像。安装包更大，性能因设备而异。' : 'Adds depth and person matting for supported media. A larger download; performance varies by device.')) + (experimental ? (zh ? ' 通用 OpenXR 为实验性支持。' : ' Generic OpenXR support is experimental.') : '');
    const pattern = new RegExp('^Thru3D-' + platform + '-.*-' + edition + '-release-.*\\.apk$', 'i');
    const asset = release?.assets?.find(item => pattern.test(item.name) && /^https:\/\/github\.com\/NorthBoundWisdom\/Thru3D-Media-Player\/releases\/download\//.test(item.browser_download_url || item.url || ''));
    link.href = asset ? (asset.browser_download_url || asset.url) : releases;
    link.textContent = asset ? ((zh ? '下载 ' : 'Download ') + platform + ' · ' + (edition === 'ai' ? 'AI' : 'No AI') + ' ↗') : (zh ? '前往 GitHub Releases ↗' : 'Open GitHub Releases ↗');
    meta.textContent = asset ? release.tag_name + ' · ' + Math.round(asset.size / 1048576) + ' MB · APK' : (zh ? '在 Assets 中选择对应设备的 APK。' : 'Choose the matching headset APK under Assets.');
  }
  form.addEventListener('change', renderDownload); renderDownload();
  const local = document.querySelector('script[data-site-script]').src.replace(/site\.js$/, 'releases.json');
  fetch(local).then(response => response.ok ? response.json() : Promise.reject()).then(data => { release = data; renderDownload(); }).catch(() => {});
})();
