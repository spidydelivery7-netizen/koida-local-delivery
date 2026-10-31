import assert from 'node:assert/strict';
import {createECDH,createHash} from 'node:crypto';
import {productionConfig,PRODUCTION_URL} from './config.mjs';
import {createProductionHandler} from './handler.mjs';
let checks=0;
const equal=(a,b)=>{assert.deepEqual(a,b);checks++;};
const ec=createECDH('prime256v1');ec.generateKeys();
const base={SUPABASE_URL:PRODUCTION_URL,HUNKART_STAFF_WORKER_ENABLED:'true',SUPABASE_SERVICE_ROLE_KEY:'fixture-only',FCM_PROJECT_ID:'hunkart-production',
 FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:'hunkart-production',client_email:'fixture@hunkart-production.iam.gserviceaccount.com',private_key:'-----BEGIN PRIVATE KEY----- fixture',token_uri:'https://oauth2.googleapis.com/token'}),
 VAPID_PUBLIC_KEY:ec.getPublicKey().toString('base64url'),VAPID_PRIVATE_KEY:ec.getPrivateKey().toString('base64url')};
equal(productionConfig(k=>base[k]).project,'hunkart-production');
for(const flag of [undefined,'false','TRUE','1',''])equal(productionConfig(k=>k==='HUNKART_STAFF_WORKER_ENABLED'?flag:base[k]),null);
for(const override of [
 {SUPABASE_URL:'https://jjitqihblpubqwbggjpv.supabase.co'},
 {SUPABASE_URL:PRODUCTION_URL+'/'}, {SUPABASE_SERVICE_ROLE_KEY:''},
 {FCM_PROJECT_ID:'hunkart-staging'}, {FCM_PROJECT_ID:undefined},
 {FCM_PROJECT_ID:'unrelated-production'},
 {FCM_PROJECT_ID:undefined,HUNKART_FCM_PROJECT_ID:'hunkart-production'},
 {FCM_SERVICE_ACCOUNT_JSON:'bad'}, {FCM_SERVICE_ACCOUNT_JSON:'null'},
 {FCM_SERVICE_ACCOUNT_JSON:base.FCM_SERVICE_ACCOUNT_JSON.replace('hunkart-production','other-project')},
 {FCM_SERVICE_ACCOUNT_JSON:base.FCM_SERVICE_ACCOUNT_JSON.replace('oauth2.googleapis.com','evil.test')},
 {FCM_SERVICE_ACCOUNT_JSON:base.FCM_SERVICE_ACCOUNT_JSON.replace('fixture@','fixture@other-')},
 {VAPID_PUBLIC_KEY:'wrong'}, {VAPID_PRIVATE_KEY:undefined}
]){assert.throws(()=>productionConfig(k=>({...base,...override})[k]));checks++;}
let calls=[],runs=0,consumed=false;
const token='a'.repeat(64);
const rpc=async(name,args)=>{calls.push({name,args});if(consumed)return false;consumed=true;return true;};
const handler=createProductionHandler({get:k=>base[k],rpc:()=>rpc,run:async()=>{runs++;return {sent:0};}});
const request=(auth='Bearer '+token,method='POST')=>new Request('https://fixture.test',{method,headers:auth?{Authorization:auth}:{}});
equal((await handler(request(undefined,'GET'))).status,405);
for(const auth of ['',token,'bearer '+token,'Bearer '+'z'.repeat(64),'Bearer '+token+'x'])equal((await handler(request(auth))).status,401);
equal(calls.length,0);equal(runs,0);
equal((await handler(request())).status,200);
equal(calls[0],{name:'hd_consume_staff_worker_token',args:{p_hash:createHash('sha256').update(token).digest('hex')}});
equal(runs,1);
equal((await handler(request())).status,401);equal(runs,1);
for(const override of [{HUNKART_STAFF_WORKER_ENABLED:undefined},{SUPABASE_URL:'https://wrong.supabase.co'},{FCM_SERVICE_ACCOUNT_JSON:'invalid'}]){
 const blocked=createProductionHandler({get:k=>({...base,...override})[k],rpc:()=>{throw Error('must not connect');},run:()=>{throw Error('must not send');}});
 equal((await blocked(request())).status,503);
}
const failure=createProductionHandler({get:k=>base[k],rpc:()=>async()=>{throw Error('secret fixture error');},run:()=>{throw Error('must not run');}});
const response=await failure(request());equal(response.status,503);equal(await response.json(),{error:'Worker temporarily unavailable'});
console.log('PASS: '+checks+' production worker configuration/authorization assertions (offline; no network)');
