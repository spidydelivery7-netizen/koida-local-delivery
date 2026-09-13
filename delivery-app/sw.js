const VAPID_PUBLIC_KEY = "BEyKFl_KeSmIboBWWUhfItErCRw9AlwjoVRq55NBedCSX_iLskyLH2Bm4ZmCc4e3ZAWBMjn07NAEU5TeIcSqObg";
const VAPID_VERSION = "hunkart-staff-vapid-20260912-v1";

function urlBase64ToUint8Array(value) {
  const padding = "=".repeat((4 - value.length % 4) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  return Uint8Array.from([...raw].map(char => char.charCodeAt(0)));
}

export async function ensureStaffPushSubscription({ sb, user, role, serviceWorkerUrl, scope }) {
  if (!sb || !user?.id || !["admin", "shopkeeper", "delivery_boy"].includes(role)) return false;
  if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) return false;

  const permission = Notification.permission === "default"
    ? await Notification.requestPermission()
    : Notification.permission;
  if (permission !== "granted") return false;

  const registration = await navigator.serviceWorker.register(serviceWorkerUrl, scope ? { scope } : undefined);
  await navigator.serviceWorker.ready;

  let subscription = await registration.pushManager.getSubscription();
  const versionKey = `hunkart_staff_push_version_${role}`;
  if (subscription && localStorage.getItem(versionKey) !== VAPID_VERSION) {
    await subscription.unsubscribe().catch(() => {});
    subscription = null;
  }
  if (!subscription) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
    });
  }

  const json = subscription.toJSON();
  if (!json.endpoint || !json.keys?.p256dh || !json.keys?.auth) return false;

  const { error } = await sb.from("staff_push_subscriptions").upsert({
    user_id: user.id,
    role,
    endpoint: json.endpoint,
    p256dh: json.keys.p256dh,
    auth_key: json.keys.auth,
    user_agent: navigator.userAgent,
    updated_at: new Date().toISOString()
  }, { onConflict: "endpoint" });
  if (error) throw error;

  localStorage.setItem(versionKey, VAPID_VERSION);
  return true;
}
