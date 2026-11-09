const CACHE = "fiyatgor-v45";
const FILES = [
  "./",
  "index.html",
  "styles.css",
  "app.js",
  "scale.js",
  "icerik.js",
  "etiket-duzen.js",
  "etiket.js",
  "ocr.js",
  "vendor/ocr/tesseract.min.js",
  "pwa/manifest.webmanifest",
  "pwa/icon.svg",
  "pwa/icon-192.png",
  "pwa/icon-512.png",
  "pwa/apple-touch-icon.png",
  "vendor/zxing.min.js",
  "vendor/xlsx.full.min.js"
];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

function yedek(req) {
  return caches.match(req, { ignoreSearch: true }).then(r => r || (req.mode === "navigate" ? caches.match("index.html").then(i => i || caches.match("./")) : undefined));
}

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin || url.pathname.includes("/api/")) return;
  e.respondWith((async () => {
    try {
      const res = await fetch(req);
      if (res.ok) {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy));
        return res;
      }
      if (res.status >= 500) { const c = await yedek(req); if (c) return c; }
      return res;
    } catch (err) {
      const c = await yedek(req);
      if (c) return c;
      throw err;
    }
  })());
});
