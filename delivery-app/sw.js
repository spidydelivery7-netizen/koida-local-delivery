const CACHE_NAME = "hunkart-delivery-v2";

const APP_FILES = [
  "/delivery-app/",
  "/delivery-app/index.html",
  "/delivery-app/manifest.webmanifest",
  "/config.js",
  "/icons/icon-192.png",
  "/icons/icon-512.png"
];

self.addEventListener("install", (event) => {
  self.skipWaiting();

  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_FILES))
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_NAME)
            .map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;

  if (req.method !== "GET") return;

  const url = new URL(req.url);

  // Authentication, database and payment traffic must always stay network-live.
  if (
    url.hostname.includes("supabase") ||
    url.hostname.includes("razorpay")
  ) {
    return;
  }

  // Keep app navigations fresh, but retain the latest successful page offline.
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
          return response;
        })
        .catch(() =>
          caches.match(req).then(
            (cached) =>
              cached ||
              caches.match("/delivery-app/index.html") ||
              caches.match("/delivery-app/")
          )
        )
    );
    return;
  }

  // Same-origin static assets use cache fallback.
  if (url.origin === self.location.origin) {
    event.respondWith(
      caches.match(req).then(
        (cached) =>
          cached ||
          fetch(req).then((response) => {
            if (response.ok) {
              const copy = response.clone();
              caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
            }
            return response;
          })
      )
    );
  }
});

self.addEventListener("push", event => {
  let data = {};
  try { data = event.data?.json() || {}; } catch { data = { body: event.data?.text() }; }
  event.waitUntil(self.registration.showNotification(data.title || "HUNKART • Delivery Assigned", {
    body: data.body || "A delivery has been assigned to you.",
    icon: "/icons/icon-192.png",
    badge: "/icons/icon-192.png",
    tag: data.tag || "hunkart-delivery-assignment",
    renotify: true,
    requireInteraction: true,
    vibrate: [500, 180, 500, 180, 700, 250, 900],
    data: { url: data.url || "/delivery-app/" }
  }));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const url = event.notification?.data?.url || "/delivery-app/";
  event.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list => {
    const client = list[0];
    if (client) { client.navigate(url); return client.focus(); }
    return clients.openWindow(url);
  }));
});
