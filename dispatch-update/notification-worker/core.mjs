// No credentials, endpoints or arbitrary messages accepted from the caller.
export async function deliverForOrder(orderId, deps){
 if(typeof orderId!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(orderId))return {status:400,error:'Invalid order'};
 if(!await deps.authorize(orderId))return {status:403,error:'Order access denied'};
 if(!deps.configured)return {status:503,error:'Notification service is not configured. Intent remains queued.'};
 const jobs=await deps.claim(orderId);let sent=0,pending=0;
 for(const job of jobs){
  try{await deps.send(job);await deps.ack(job.id,job.lease_token,'sent',null);sent++;}
  catch(e){await deps.ack(job.id,job.lease_token,e.permanent?'failed':'retry','Notification delivery failed');pending++;}
 }
 return {status:200,sent,pending};
}
export function allowedPushEndpoint(endpoint){
 try{const u=new URL(endpoint);return u.protocol==='https:'&&(u.hostname==='fcm.googleapis.com'||u.hostname==='updates.push.services.mozilla.com'||u.hostname==='web.push.apple.com'||u.hostname.endsWith('.notify.windows.com'));}catch{return false;}
}
