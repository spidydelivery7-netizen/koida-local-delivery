import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import webpush from 'npm:web-push@3.6.7';
import { deliverForOrder, allowedPushEndpoint } from './core.mjs';
const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
Deno.serve(async(req:Request)=>{
 const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'POST required'},405);
 const authorization=req.headers.get('Authorization');
 if(!authorization?.startsWith('Bearer '))return reply({error:'Login required'},401);
 const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const userClient=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error:userError}=await userClient.auth.getUser();
 if(userError||!user)return reply({error:'Login required'},401);
 let body;try{body=await req.json()}catch{return reply({error:'Invalid request'},400)}
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const pub=Deno.env.get('VAPID_PUBLIC_KEY'),priv=Deno.env.get('VAPID_PRIVATE_KEY');
 try{
  const result=await deliverForOrder(body?.order_id,{
   configured:!!pub&&!!priv,
   authorize:async(id:string)=>{const {data,error}=await userClient.rpc('hd_can_notify',{p_order_id:id});if(error)throw error;return data===true},
   claim:async(id:string)=>{const {data,error}=await admin.rpc('hd_claim_notifications',{p_order_id:id});if(error)throw error;return data||[]},
   ack:async(id:string,token:string,status:string,errorText:string|null)=>{const {error}=await admin.rpc('hd_ack_notification',{p_id:id,p_token:token,p_status:status,p_error:errorText});if(error)throw error},
   send:async(job:{customer_id:string,payload:unknown})=>{
    const {data,error}=await admin.from('customer_push_subscriptions').select('endpoint,p256dh,auth_key').eq('customer_id',job.customer_id);if(error)throw error;
    const subs=(data||[]).filter(s=>allowedPushEndpoint(s.endpoint));
    if(!subs.length){const e=new Error('No eligible subscription');Object.assign(e,{permanent:true});throw e;}
    const results=await Promise.allSettled(subs.map(s=>webpush.sendNotification({endpoint:s.endpoint,keys:{p256dh:s.p256dh,auth:s.auth_key}},JSON.stringify(job.payload),{vapidDetails:{subject:'https://hunkart.com',publicKey:pub!,privateKey:priv!},TTL:300})));
    if(!results.some(r=>r.status==='fulfilled'))throw new Error('Push delivery failed');
   }
  });return reply(result,result.status);
 }catch{return reply({error:'Notification delivery pending; retry later'},503)}
});
