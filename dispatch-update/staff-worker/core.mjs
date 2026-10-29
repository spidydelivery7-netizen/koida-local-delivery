export function allowedEndpoint(endpoint) {
 try {
  const u=new URL(endpoint);
  return u.protocol==='https:' && !u.port && !u.username && !u.password &&
   (['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com'].includes(u.hostname)||u.hostname.endsWith('.notify.windows.com'));
 } catch { return false; }
}
export async function runStaffBatch(deps) {
 const claims=await deps.claim();
 const outcomes=await Promise.all(claims.map(async job=>{
  try {
   const delivery=await deps.delivery(job.id,job.lease_token);
   if(!delivery)return 'cancelled';
   const remaining=Math.floor((Date.parse(delivery.payload.expiresAt)-Date.now())/1000);
   const ttl=Math.min(delivery.ttl,remaining);
   if(!Number.isFinite(ttl)||ttl<1){await deps.ack(job.id,job.lease_token,'retry');return 'cancelled';}
   const subs=(delivery.subscriptions||[]).filter(s=>allowedEndpoint(s.endpoint));
   if(!subs.length){await deps.ack(job.id,job.lease_token,'retry');return 'retry';}
   const results=await Promise.allSettled(subs.map(s=>deps.send(s,delivery.payload,ttl)));
   // Sent means provider acceptance on at least one device, not proof of viewing.
   const sent=results.some(r=>r.status==='fulfilled');
   const permanent=!sent&&results.every(r=>r.status==='rejected'&&[404,410].includes(r.reason?.statusCode));
   const status=sent?'sent':permanent?'failed':'retry';
   await deps.ack(job.id,job.lease_token,status);return status;
  }catch{return 'unacknowledged';}
 }));
 return Object.fromEntries(['sent','retry','failed','cancelled','unacknowledged'].map(k=>[k,outcomes.filter(v=>v===k).length]));
}
