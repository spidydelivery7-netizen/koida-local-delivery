const VAPID_PUBLIC_KEY = "BEyKFl_KeSmIboBWWUhfItErCRw9AlwjoVRq55NBedCSX_iLskyLH2Bm4ZmCc4e3ZAWBMjn07NAEU5TeIcSqObg";
const VAPID_VERSION = "hunkart-staff-vapid-20260912-v1";
const STAGING_URL = "https://jjitqihblpubqwbggjpv.supabase.co";
const STAGING_PUBLIC_KEY = "BGFC4eGhVc-3TRqTi6uDZ56XyuD65Et2R_2FEjlAm2Za701dtOEwwe4tHQ6DykvAnuBPrj05Bq8iudR8fJaz2oM";

function urlBase64ToUint8Array(value) {
  const padding = "=".repeat((4 - value.length % 4) % 4);
  const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  return Uint8Array.from([...raw].map(char => char.charCodeAt(0)));
}

export async function ensureStaffPushSubscription({ sb, user, role, serviceWorkerUrl, scope }) {
  if (!sb || !user?.id || !["admin", "shopkeeper", "delivery_boy"].includes(role)) return false;
  if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) return false;

  const staging = String(sb.supabaseUrl || "").replace(/\/$/, "") === STAGING_URL;
  const publicKey = staging ? STAGING_PUBLIC_KEY : VAPID_PUBLIC_KEY;
  const version = staging ? "hunkart-staging-vapid-20261028-v1" : VAPID_VERSION;
  const permission = Notification.permission === "default"
    ? await Notification.requestPermission()
    : Notification.permission;
  if (permission !== "granted") return false;

  const registration = await navigator.serviceWorker.register(serviceWorkerUrl, scope ? { scope } : undefined);
  await navigator.serviceWorker.ready;

  let subscription = await registration.pushManager.getSubscription();
  const versionKey = `hunkart_staff_push_version_${staging ? "staging_" : ""}${role}`;
  if (subscription && localStorage.getItem(versionKey) !== version) {
    await subscription.unsubscribe().catch(() => {});
    subscription = null;
  }
  if (!subscription) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(publicKey)
    });
  }

  const json = subscription.toJSON();
  if (!json.endpoint || !json.keys?.p256dh || !json.keys?.auth) return false;

  const { error } = await sb.rpc(staging ? "hd_save_staff_push_subscription" : "save_staff_push_subscription", {
    p_role: role,
    p_endpoint: json.endpoint,
    p_p256dh: json.keys.p256dh,
    p_auth: json.keys.auth,
    p_user_agent: navigator.userAgent
  });
  if (error) throw error;

  localStorage.setItem(versionKey, version);
  return true;
}
