import {createECDH} from 'node:crypto';
import {Buffer} from 'node:buffer';

export const PRODUCTION_URL='https://amnqqxgmqciipcortpmi.supabase.co';
export const PRODUCTION_FIREBASE_PROJECT='hunkart-production';
// No fallback to staging, client credentials, or an inferred Firebase project.
export function productionConfig(get) {
 if(get('SUPABASE_URL')!==PRODUCTION_URL)throw Error('Wrong Supabase project');
 if(get('HUNKART_STAFF_WORKER_ENABLED')!=='true')return null;
 const service=get('SUPABASE_SERVICE_ROLE_KEY');
 if(typeof service!=='string'||!service.trim())throw Error('Missing server credential');
 const project=get('FCM_PROJECT_ID');
 if(project!==PRODUCTION_FIREBASE_PROJECT)throw Error('Invalid production Firebase project');
 let account;
 try{account=JSON.parse(get('FCM_SERVICE_ACCOUNT_JSON')||'');}catch{throw Error('Missing Firebase server configuration');}
 if(account?.project_id!==project||account.type!=='service_account'||
    typeof account.client_email!=='string'||!account.client_email.endsWith('@'+project+'.iam.gserviceaccount.com')||
    typeof account.private_key!=='string'||!account.private_key.includes('-----BEGIN PRIVATE KEY-----')||
    account.token_uri!=='https://oauth2.googleapis.com/token')throw Error('Firebase server identity mismatch');
 const pub=get('VAPID_PUBLIC_KEY')?.trim(),priv=get('VAPID_PRIVATE_KEY')?.trim();
 try{
  const ec=createECDH('prime256v1');ec.setPrivateKey(Buffer.from(priv||'','base64url'));
  if(ec.getPublicKey().toString('base64url')!==pub)throw Error();
 }catch{throw Error('VAPID key pair mismatch');}
 return {url:PRODUCTION_URL,service,project,account,pub,priv};
}
