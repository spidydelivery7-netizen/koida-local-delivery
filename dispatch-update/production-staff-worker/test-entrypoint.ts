// Real Deno entrypoint/import smoke test. No listener, credentials or network.
let captured: ((req:Request)=>Promise<Response>)|undefined;
const originalServe=Deno.serve,originalGet=Deno.env.get;
try{
 Object.defineProperty(Deno,'serve',{configurable:true,value:(handler:any)=>{captured=handler;}});
 Object.defineProperty(Deno.env,'get',{configurable:true,value:(name:string)=>name==='SUPABASE_URL'?'https://amnqqxgmqciipcortpmi.supabase.co':undefined});
 await import('./index.ts');
 if(!captured)throw Error('Entrypoint did not register handler');
 let checks=0;
 for(const [method,auth,status] of [
  ['GET','',405],['POST','',401],['POST','Bearer invalid',401],
  ['POST','Bearer '+'a'.repeat(64),503]
 ] as const){
  const response=await captured(new Request('https://fixture.invalid',{method,headers:auth?{Authorization:auth}:{}}));
  if(response.status!==status)throw Error('Unexpected entrypoint response');checks++;
 }
 console.log('PASS: '+checks+' real Deno entrypoint/import checks; worker disabled, no network permission');
}finally{
 Object.defineProperty(Deno,'serve',{configurable:true,value:originalServe});
 Object.defineProperty(Deno.env,'get',{configurable:true,value:originalGet});
}
