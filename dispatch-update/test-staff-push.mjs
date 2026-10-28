import assert from 'node:assert/strict';
import {ensureStaffPushSubscription} from '../staff-push.js';
const prod='BEyKFl_KeSmIboBWWUhfItErCRw9AlwjoVRq55NBedCSX_iLskyLH2Bm4ZmCc4e3ZAWBMjn07NAEU5TeIcSqObg';
const staging='BGFC4eGhVc-3TRqTi6uDZ56XyuD65Et2R_2FEjlAm2Za701dtOEwwe4tHQ6DykvAnuBPrj05Bq8iudR8fJaz2oM';
for(const [url,key,rpc] of [['https://jjitqihblpubqwbggjpv.supabase.co',staging,'hd_save_staff_push_subscription'],['https://amnqqxgmqciipcortpmi.supabase.co',prod,'save_staff_push_subscription']]){
 let actualKey,actualRpc,stored;const reg={pushManager:{getSubscription:async()=>null,subscribe:async opts=>{actualKey=Buffer.from(opts.applicationServerKey).toString('base64url');return {toJSON:()=>({endpoint:'https://fcm.googleapis.com/test',keys:{p256dh:'test',auth:'test'}})}}}};
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{userAgent:'Unit test',serviceWorker:{register:async()=>reg,ready:Promise.resolve(reg)}}});globalThis.window={PushManager:class{},Notification:class{}};globalThis.Notification={permission:'granted'};globalThis.localStorage={getItem:()=>null,setItem:(k,v)=>stored=[k,v]};
 const sb={supabaseUrl:url,rpc:async(name,args)=>{actualRpc=name;return {error:null}}};
 assert.equal(await ensureStaffPushSubscription({sb,user:{id:'synthetic'},role:'shopkeeper',serviceWorkerUrl:'/sw.js'}),true);
 assert.equal(actualKey,key);assert.equal(actualRpc,rpc);assert.equal(stored[0].includes('staging'),url.includes('jjitqih'));
}
assert.equal(await ensureStaffPushSubscription({sb:{},user:{id:'synthetic'},role:'customer'}),false);
console.log('PASS: staging key/RPC selected; production key/RPC preserved; customer role refused (9 assertions).');
