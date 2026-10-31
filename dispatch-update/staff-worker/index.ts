import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import webpush from 'npm:web-push@3.6.7';
import {createECDH} from 'node:crypto';
import {Buffer} from 'node:buffer';
import {runStaffBatch} from './core.mjs';
import {firebaseAccessToken} from '../native-fcm/oauth.mjs';
import {sendFcm} from '../native-fcm/send.mjs';
const STAGING_URL='https://jjitqihblpubqwbggjpv.supabase.co';
Deno.serve(async req=>{
 if(req.method!=='POST')return Response.json({error:'POST required'},{status:405});
 const token=(req.headers.get('Authorization')||'').replace(/^Bearer /,'');
 if(token.length!==64)return Response.json({error:'Unauthorized'},{status:401});
 const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token)))).map(x=>x.toString(16).padStart(2,'0')).join('');
 if(Deno.env.get('SUPABASE_URL')!==STAGING_URL)return Response.json({error:'Staging deployment only'},{status:403});
 const pub=Deno.env.get('VAPID_PUBLIC_KEY')?.trim(),priv=Deno.env.get('VAPID_PRIVATE_KEY')?.trim();
 try {
  const ec=createECDH('prime256v1');ec.setPrivateKey(Buffer.from(priv||'','base64url'));
  if(ec.getPublicKey().toString('base64url')!==pub)throw new Error('Mismatch');
 }catch{return Response.json({error:'VAPID key pair is not configured correctly'},{status:503});}
 const sb=createClient(STAGING_URL,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const configuredAccount=Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
 let account:Record<string,string>|null=null;
 try {if(configuredAccount){account=JSON.parse(configuredAccount);if(account.project_id!=='hunkart-staging')throw Error('Unexpected Firebase project');}}
 catch {return Response.json({error:'Invalid staging FCM configuration'},{status:503});}
 let accessToken:string|undefined;
 async function rpc(name:string,args?:Record<string,unknown>){const {data,error}=await sb.rpc(name,args);if(error)throw error;return data;}
 try{
  if(await rpc('hd_consume_staff_worker_token',{p_hash:digest})!==true)return Response.json({error:'Unauthorized'},{status:401});
  const result=await runStaffBatch({
   claim:()=>rpc('hd_claim_staff_notifications'),
   delivery:(id:string,token:string)=>rpc('hd_staff_notification_delivery',{p_id:id,p_token:token}),
   ack:(id:string,token:string,status:string)=>rpc('hd_ack_staff_notification',{p_id:id,p_token:token,p_status:status}),
   send:(sub:unknown,payload:unknown,ttl:number)=>webpush.sendNotification(sub,JSON.stringify(payload),{vapidDetails:{subject:'https://hunkart.com',publicKey:pub!,privateKey:priv!},TTL:ttl,timeout:6000,urgency:'high'}),
   sendNative:async (deviceToken:string,payload:Record<string,unknown>)=>{
    if(!account)return {status:'retry'};
    if(!accessToken)accessToken=await firebaseAccessToken(account);
    return sendFcm({fetchImpl:fetch,accessToken,projectId:'hunkart-staging',deviceToken,
      event:{kind:payload.event==='rider_offer'?'rider_offer':'shop_order_ready',expiresAt:payload.expiresAt,
        orderId:payload.orderId,offerId:payload.offerId}});
   }
  });return Response.json(result);
 }catch{return Response.json({error:'Worker temporarily unavailable'},{status:503});}
});
