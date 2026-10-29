import { fcmMessage, classifyFcm } from './core.mjs';

// Credentials are supplied by the trusted runtime, never by an app client.
export async function sendFcm({fetchImpl, accessToken, projectId, deviceToken, event, now = Date.now(), signal}) {
  if (typeof accessToken !== 'string' || !accessToken.trim()) throw new Error('Missing access token');
  if (typeof projectId !== 'string' || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)) throw new Error('Invalid project id');
  const body = fcmMessage(deviceToken, event, now);
  if (!body) return {status:'expired'};
  let response;
  try {
    response = await fetchImpl('https://fcm.googleapis.com/v1/projects/' + projectId + '/messages:send', {
      method:'POST',
      headers:{'Authorization':'Bearer ' + accessToken, 'Content-Type':'application/json'},
      body:JSON.stringify(body), signal
    });
  } catch { return {status:'retry'}; }
  if (response.ok) return {status:'sent'};
  let result;
  try { result = await response.json(); } catch { result = {}; }
  const details = Array.isArray(result?.error?.details) ? result.error.details : [];
  const code = details.find(item => item?.['@type'] === 'type.googleapis.com/google.firebase.fcm.v1.FcmError')?.errorCode;
  return {status:classifyFcm(response.status, code)};
}
