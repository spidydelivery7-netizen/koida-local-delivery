import assert from 'node:assert/strict';
import {attachNativeStaffRegistration} from './production-registration.mjs';
const pause=()=>new Promise(r=>setTimeout(r,10));
function fixture(overrides={}){
 const events=new Map(),calls=[],states=[];let callback,user='one',fail=false;
 const host={location:{origin:'https://hunkart.com',pathname:'/shopkeeper-app/'},setTimeout,
  CustomEvent:class{constructor(type,args){this.type=type;this.detail=args.detail;}},
  dispatchEvent:e=>states.push(e.detail.state),addEventListener:(n,f)=>events.set(n,f),removeEventListener:n=>events.delete(n),
  HunkartNative:{requestToken(){calls.push('request');}}};
 const sb={auth:{getSession:async()=>({data:{session:user?{user:{id:user}}:null}}),
  onAuthStateChange:f=>{callback=f;return {data:{subscription:{unsubscribe(){}}}};},
  signOut:async()=>{calls.push('logout');user=null;return {error:null};}},
  rpc:async(n,a)=>{calls.push([n,a]);return {data:true,error:fail?{message:'offline'}:null};}};
 const cleanup=attachNativeStaffRegistration({sb,role:'shopkeeper',supabaseUrl:'https://amnqqxgmqciipcortpmi.supabase.co',host,...overrides});
 return {host,sb,calls,states,cleanup,emit:t=>events.get('hunkart-native-token')?.({detail:{token:t}}),auth:(e,u)=>{user=u;callback?.(e);},fail:v=>{fail=v;}};
}
const a='a'.repeat(64),b='b'.repeat(64);
let f=fixture();f.emit(a);await pause();assert.equal(f.calls[1][0],'hd_save_native_device');
f.emit(a);f.auth('TOKEN_REFRESHED','one');await pause();assert.equal(f.calls.length,2);
f.emit(b);await pause();assert.equal(f.calls[2][0],'hd_save_native_device');assert.equal(f.calls[3][0],'hd_remove_native_device');assert.equal(f.calls[3][1].p_token,a);
await f.sb.auth.signOut();assert.equal(f.calls.at(-1),'logout');assert.equal(f.calls.at(-2)[1].p_token,b);
f=fixture();f.emit(a);f.emit(b);await pause();await f.sb.auth.signOut();assert.equal(f.calls.at(-1),'logout');
f=fixture();f.auth('SIGNED_OUT',null);f.emit(a);await pause();assert.equal(f.calls.length,1);
f.auth('SIGNED_IN','two');await pause();assert.equal(f.calls[1][0],'hd_save_native_device');
f.fail(true);await assert.rejects(f.sb.auth.signOut(),/cleanup failed/);assert.ok(!f.calls.includes('logout'));
f.fail(false);await f.sb.auth.signOut();assert.equal(f.calls.at(-1),'logout');
f=fixture();f.emit('bad token');await pause();assert.equal(f.calls.length,1);f.cleanup();f.emit(a);await pause();assert.equal(f.calls.length,1);
for(const overrides of [{supabaseUrl:'https://other.supabase.co'},{role:'admin'},{host:{location:{origin:'https://evil.example',pathname:'/shopkeeper-app/'}}},{host:{location:{origin:'https://hunkart.com',pathname:'/delivery-app/'}}}]){
 f=fixture(overrides);assert.equal(f.calls.length,0);
}
console.log('PASS: production registration, deduplication, rotation, login, logout failure/retry, cleanup and origin/role gates');
// Logout waits for a save already in flight, then removes that token before auth signout.
f=fixture();let finish;
const rpc=f.sb.rpc;
f.sb.rpc=async(name,args)=>{
 if(name==='hd_save_native_device')await new Promise(resolve=>{finish=resolve;});
 return rpc(name,args);
};
f.emit(a);await pause();const leaving=f.sb.auth.signOut();
assert.ok(!f.calls.includes('logout'));finish();await leaving;
assert.deepEqual(f.calls.slice(1).map(x=>typeof x==='string'?x:x[0]),['hd_save_native_device','hd_remove_native_device','logout']);
// A failed old-token cleanup remains queued and is retried even when the new token is unchanged.
f=fixture();f.emit(a);await pause();
const realRpc=f.sb.rpc;let removeFails=true;
f.sb.rpc=async(name,args)=>name==='hd_remove_native_device'&&removeFails?{error:{message:'offline'}}:realRpc(name,args);
f.emit(b);await pause();assert.equal(f.states.at(-1),'unavailable');
removeFails=false;f.emit(b);await pause();assert.equal(f.states.at(-1),'registered');
assert.equal(f.calls.at(-1)[0],'hd_remove_native_device');assert.equal(f.calls.at(-1)[1].p_token,a);
console.log('PASS: in-flight save/logout serialization and failed rotation cleanup retry');
