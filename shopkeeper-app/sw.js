const CACHE_NAME = "hunkart-shopkeeper-v1";

const APP_FILES = [
  "/shopkeeper.html",
  "/shopkeeper-app/manifest.webmanifest",
  "/icons/icon-192.png",
  "/icons/icon-512.png"
];

self.addEventListener("install", (event) => {
  self.skipWaiting();

  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(APP_FILES);
    })
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const copy = response.clone();

        caches.open(CACHE_NAME).then((cache) => {
          cache.put(event.request, copy);
        });

        return response;
      })
      .catch(() => {
        return caches.match(event.request).then((cached) => {
          if (cached) return cached;

          if (event.request.mode === "navigate") {
            return caches.match("/shopkeeper.html");
          }
        });
      })
  );
});

self.addEventListener("push", event => {
  let data = {};
  try { data = event.data?.json() || {}; } catch { data = { body: event.data?.text() }; }
  event.waitUntil(self.registration.showNotification(data.title || "HUNKART • New Order", {
    body: data.body || "A new order needs your attention.",
    icon: "/icons/icon-192.png",
    badge: "/icons/icon-192.png",
    tag: data.tag || "hunkart-shop-order",
    renotify: true,
    requireInteraction: true,
    vibrate: [500, 180, 500, 180, 700, 250, 900],
    data: { url: data.url || "/shopkeeper-app/" }
  }));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const url = event.notification?.data?.url || "/shopkeeper-app/";
  event.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list => {
    const client = list[0];
    if (client) { client.navigate(url); return client.focus(); }
    return clients.openWindow(url);
  }));
});
