import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import webpush from 'npm:web-push@3.6.7';
import {createProductionHandler} from './handler.mjs';
import {runStaffBatch} from '../staff-worker/core.mjs';
import {firebaseAccessToken} from '../native-fcm/oauth.mjs';
import {sendFcm} from '../native-fcm/send.mjs';

Deno.serve(createProductionHandler({
 get:(name:string)=>Deno.env.get(name),
 rpc:(config:any)=>{
  const sb=createClient(config.url,config.service,{auth:{persistSession:false,autoRefreshToken:false}});
  return async(name:string,args?:Record<string,unknown>)=>{
   const {data,error}=await sb.rpc(name,args);if(error)throw error;return data;
  };
 },
 run:async(config:any,rpc:any)=>{
  let accessToken:string|undefined;
  return runStaffBatch({
   claim:()=>rpc('hd_claim_staff_notifications'),
   delivery:(id:string,token:string)=>rpc('hd_staff_notification_delivery',{p_id:id,p_token:token}),
   ack:(id:string,token:string,status:string)=>rpc('hd_ack_staff_notification',{p_id:id,p_token:token,p_status:status}),
   send:(sub:any,payload:any,ttl:number)=>webpush.sendNotification(sub,JSON.stringify(payload),{vapidDetails:{subject:'https://hunkart.com',publicKey:config.pub,privateKey:config.priv},TTL:ttl,timeout:6000,urgency:'high'}),
   sendNative:async(deviceToken:string,payload:any)=>{
    if(!accessToken)accessToken=await firebaseAccessToken(config.account,(url:any,init:any)=>fetch(url,{...init,signal:AbortSignal.timeout(6000)}));
    return sendFcm({fetchImpl:fetch,accessToken,projectId:config.project,deviceToken,signal:AbortSignal.timeout(6000),
     event:{kind:payload.event==='rider_offer'?'rider_offer':'shop_order_ready',expiresAt:payload.expiresAt,orderId:payload.orderId,offerId:payload.offerId}});
   }
  });
 }
}));
