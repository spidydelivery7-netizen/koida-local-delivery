import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const sources=[
 ['index.ts','./index.ts'],['handler.mjs','./handler.mjs'],['config.mjs','./config.mjs'],
 ['batch-core.mjs','../staff-worker/core.mjs'],['oauth.mjs','../native-fcm/oauth.mjs'],
 ['send.mjs','../native-fcm/send.mjs'],['fcm-core.mjs','../native-fcm/core.mjs']
];
const replacements={
 'index.ts':[['../staff-worker/core.mjs','./batch-core.mjs'],['../native-fcm/oauth.mjs','./oauth.mjs'],['../native-fcm/send.mjs','./send.mjs']],
 'send.mjs':[['./core.mjs','./fcm-core.mjs']]
};
export function deploymentPackage(){
 const files=sources.map(([name,path])=>{
  let content=readFileSync(new URL(path,import.meta.url),'utf8');
  for(const [before,after] of replacements[name]||[]){
   if(content.split(before).length!==2)throw Error('Unexpected source import: '+name);
   content=content.replace(before,after);
  }
  if(/from\s+['"]\.\.\//.test(content))throw Error('Package contains escaping import');
  return {name,content};
 });
 const names=new Set(files.map(f=>f.name));
 for(const file of files){
  for(const m of file.content.matchAll(/from\s+['"]\.\/([^'"]+)['"]/g)){
   if(!names.has(m[1]))throw Error('Missing local dependency: '+m[1]);
  }
 }
 return {name:'dispatch-staff-worker',entrypoint_path:'index.ts',verify_jwt:false,files};
}
export function packageManifest(pkg){
 return {name:pkg.name,entrypoint_path:pkg.entrypoint_path,verify_jwt:pkg.verify_jwt,
  files:pkg.files.map(f=>({name:f.name,sha256:createHash('sha256').update(f.content).digest('hex')}))};
}
