// Enabled-path integration using actual imports/SDK/OAuth signing with generated
// credentials and intercepted transport. Run WITHOUT any network/env permission.
import {createECDH,generateKeyPairSync} from 'node:crypto';
const ec=createECDH('prime256v1');ec.generateKeys();
const {privateKey}=generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{type:'pkcs8',format:'pem'},publicKeyEncoding:{type:'spki',format:'pem'}});
const env:Record<string,string>={
 SUPABASE_URL:'https://amnqqxgmqciipcortpmi.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'synthetic-server-key',
 HUNKART_STAFF_WORKER_ENABLED:'true',FCM_PROJECT_ID:'hunkart-production',
 VAPID_PUBLIC_KEY:ec.getPublicKey().toString('base64url'),VAPID_PRIVATE_KEY:ec.getPrivateKey().toString('base64url'),
 FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:'hunkart-production',client_email:'fixture@hunkart-production.iam.gserviceaccount.com',private_key:privateKey,token_uri:'https://oauth2.googleapis.com/token'})
};
let handler:any;const calls:string[]=[];const consumed=new Set<string>();let mode='success',ack:any;
let checks=0;const ok=(value:boolean,label:string)=>{if(!value)throw Error(label);checks++;};
const original={serve:Deno.serve,get:Deno.env.get,fetch:globalThis.fetch};
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json'}});
try{
 Object.defineProperty(Deno,'serve',{configurable:true,value:(h:any)=>{handler=h;}});
 Object.defineProperty(Deno.env,'get',{configurable:true,value:(key:string)=>env[key]});
 globalThis.fetch=async(input:any,init:any)=>{
  const url=String(input);const body=typeof init?.body==='string'?JSON.parse(init.body):null;
  if(url.startsWith(env.SUPABASE_URL+'/rest/v1/rpc/')){
   const name=url.split('/').pop()!;calls.push(name);
   if(name==='hd_consume_staff_worker_token'){
    ok(/^[a-f0-9]{64}$/.test(body.p_hash),'capability hashed');
    if(consumed.has(body.p_hash))return json(false);consumed.add(body.p_hash);return json(true);
   }
   if(name==='hd_claim_staff_notifications')return json([{id:'fixture-job',lease_token:'fixture-lease'}]);
   if(name==='hd_staff_notification_delivery')return json({subscriptions:[],nativeDevices:['A'.repeat(64)],ttl:30,payload:{event:'rider_offer',orderId:'fixture-order',offerId:'fixture-offer',expiresAt:new Date(Date.now()+30000).toISOString()}});
   if(name==='hd_ack_staff_notification'){ack=body;return json(null);}
  }
  if(url==='https://oauth2.googleapis.com/token'){
   calls.push('oauth');
   ok(new URLSearchParams(init.body).get('assertion')?.split('.').length===3,'signed OAuth assertion');
   return json({access_token:'synthetic-oauth-token'});
  }
  if(url==='https://fcm.googleapis.com/v1/projects/hunkart-production/messages:send'){
   calls.push('fcm');ok(body.message.data.kind==='rider_offer','native event mapped');
   ok(body.message.android.priority==='HIGH','high priority');
   return mode==='retry'?json({error:{}},503):json({name:'fixture-message'});
  }
  throw Error('Unexpected outbound request blocked');
 };
 await import('./index.ts');
 const req=(token:string)=>new Request('https://fixture.invalid',{method:'POST',headers:{Authorization:'Bearer '+token.repeat(64)}});
 let response=await handler(req('a'));
 ok(response.status===200,'enabled handler success');ok((await response.json()).sent===1,'provider acceptance counted');
 ok(ack.p_id==='fixture-job'&&ack.p_token==='fixture-lease'&&ack.p_status==='sent','correct lease acknowledged');
 ok(calls.join(',')==='hd_consume_staff_worker_token,hd_claim_staff_notifications,hd_staff_notification_delivery,oauth,fcm,hd_ack_staff_notification','consume precedes claims and providers');
 const count=calls.length;response=await handler(req('a'));ok(response.status===401,'replay denied');ok(calls.length===count+1,'replay never claims or sends');
 mode='retry';response=await handler(req('b'));ok(response.status===200,'provider retry handled');ok((await response.json()).retry===1&&ack.p_status==='retry','transient provider failure queues retry');
 const before=calls.length;env.HUNKART_STAFF_WORKER_ENABLED='false';response=await handler(req('c'));ok(response.status===503,'disabled worker stopped');ok(calls.length===before,'disabled makes no RPC/provider calls');
 console.log('PASS: '+checks+' enabled real-entrypoint integration checks; generated fixtures, intercepted transport, no network permission');
}finally{
 globalThis.fetch=original.fetch;
 Object.defineProperty(Deno,'serve',{configurable:true,value:original.serve});
 Object.defineProperty(Deno.env,'get',{configurable:true,value:original.get});
}
