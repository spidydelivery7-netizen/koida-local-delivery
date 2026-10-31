import {productionConfig} from './config.mjs';

// Dependencies are injected so authorization ordering is executable offline.
export function createProductionHandler(deps) {
 return async req=>{
  if(req.method!=='POST')return Response.json({error:'POST required'},{status:405});
  const match=/^Bearer ([a-f0-9]{64})$/.exec(req.headers.get('Authorization')||'');
  if(!match)return Response.json({error:'Unauthorized'},{status:401});
  let config;
  try{config=productionConfig(deps.get);}catch{return Response.json({error:'Worker configuration unavailable'},{status:503});}
  if(!config)return Response.json({error:'Worker disabled'},{status:503});
  try{
   const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(match[1])))).map(x=>x.toString(16).padStart(2,'0')).join('');
   const rpc=deps.rpc(config);
   if(await rpc('hd_consume_staff_worker_token',{p_hash:hash})!==true)return Response.json({error:'Unauthorized'},{status:401});
   return Response.json(await deps.run(config,rpc));
  }catch{return Response.json({error:'Worker temporarily unavailable'},{status:503});}
 };
}
