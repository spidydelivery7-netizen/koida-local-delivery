const CACHE_NAME = "hunkart-delivery-dispatch-v5";

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
    caches.open(CACHE_NAME).then((cache) =>
      Promise.allSettled(APP_FILES.map((file) => cache.add(file)))
    )
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

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { body: event.data ? event.data.text() : "" };
  }


  // Ignore delayed/invalid expiry alerts; legacy payloads remain supported.
  if (data.expiresAt != null) {
    const expires = Date.parse(data.expiresAt);
    if (!Number.isFinite(expires) || expires <= Date.now()) return;
  }

  const notification = {
    body: data.body || "A new delivery has been assigned to you.",
    icon: data.icon || "/icons/icon-192.png",
    badge: data.badge || "/icons/icon-192.png",
    tag: data.tag || "hunkart-delivery-assignment",
    renotify: true,
    requireInteraction: true,
    silent: false,
    vibrate: [700, 200, 700, 200, 900, 250, 1200, 300, 1500],
    data: {
      url: data.url || "/delivery-app/",
      orderId: data.orderId || null
    }
  };

  event.waitUntil(
    self.registration.showNotification(
      data.title || "HUNKART • New Delivery Assigned",
      notification
    )
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = new URL(
    event.notification?.data?.url || "/delivery-app/",
    self.location.origin
  ).href;

  event.waitUntil(
    clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then(async (windowClients) => {
        const deliveryClient = windowClients.find((client) =>
          client.url.startsWith(`${self.location.origin}/delivery-app`)
        );

        if (deliveryClient) {
          await deliveryClient.navigate(targetUrl);
          return deliveryClient.focus();
        }

        return clients.openWindow(targetUrl);
      })
  );
});
