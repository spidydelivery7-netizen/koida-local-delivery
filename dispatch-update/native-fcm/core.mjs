// Pure helpers for staging FCM delivery. No credentials or database access.
export function fcmMessage(token, event, now = Date.now()) {
  if (typeof token !== 'string' || token.length < 20 || token.length > 4096 || /\s/.test(token)) throw new Error('Invalid device token');
  if (!event || !['shop_order','rider_offer'].includes(event.kind)) throw new Error('Invalid event');
  const expiry = Date.parse(event.expiresAt);
  if (!Number.isFinite(expiry) || expiry <= now) return null;
  const seconds = Math.min(3600, Math.floor((expiry - now) / 1000));
  if (seconds < 1) return null;
  return {message:{token, data:{kind:event.kind, expiresAt:new Date(expiry).toISOString()}, android:{priority:'HIGH',ttl:seconds+'s'}}};
}
export function classifyFcm(status, errorCode) {
  if (status >= 200 && status < 300) return 'sent';
  if (errorCode === 'UNREGISTERED') return 'invalid_token';
  if (status === 429 || status >= 500 || status === 0) return 'retry';
  return 'failed';
}
