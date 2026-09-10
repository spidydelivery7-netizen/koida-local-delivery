const CACHE = "hunkart-shell-v2";
const SHELL = [
  "/",
  "/manifest.webmanifest",
  "/icons/icon-192.png",
  "/icons/icon-512.png"
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(SHELL))
  );
  self.skipWaiting();
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(key => key !== CACHE)
          .map(key => caches.delete(key))
      )
    )
  );

  self.clients.claim();
});

self.addEventListener("fetch", event => {
  const req = event.request;

  if (req.method !== "GET") return;

  // Never cache Supabase / Razorpay / API calls.
  const url = new URL(req.url);

  if (
    url.hostname.includes("supabase") ||
    url.hostname.includes("razorpay")
  ) {
    return;
  }

  // Network-first for HTML navigation so deployments stay fresh.
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then(res => {
          const copy = res.clone();

          caches.open(CACHE).then(cache => {
            cache.put(req, copy);
          });

          return res;
        })
        .catch(() =>
          caches.match(req).then(res =>
            res || caches.match("/")
          )
        )
    );

    return;
  }

  // Static assets: cache fallback.
  event.respondWith(
    caches.match(req).then(cached =>
      cached ||
      fetch(req).then(res => {
        if (res.ok && url.origin === self.location.origin) {
          const copy = res.clone();

          caches.open(CACHE).then(cache => {
            cache.put(req, copy);
          });
        }

        return res;
      })
    )
  );
});

self.addEventListener("push", event => {
  let data = {};

  if (event.data) {
    try {
      data = event.data.json();
    } catch {
      data = {
        body: event.data.text()
      };
    }
  }

  const title = data.title || "HUNKART";

  const options = {
    body: data.body || "You have a new update.",
    icon: data.icon || "/icons/icon-192.png",
    badge: data.badge || "/icons/icon-192.png",
    tag: data.tag || "hunkart-notification",
    vibrate: [200, 100, 200],
    data: {
      url: data.url || "/"
    }
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});

self.addEventListener("notificationclick", event => {
  event.notification.close();

  const targetUrl =
    event.notification?.data?.url || "/";

  event.waitUntil(
    clients.matchAll({
      type: "window",
      includeUncontrolled: true
    }).then(windowClients => {
      for (const client of windowClients) {
        if ("focus" in client) {
          if ("navigate" in client) {
            client.navigate(targetUrl);
          }

          return client.focus();
        }
      }

      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});
