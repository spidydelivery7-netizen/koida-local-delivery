import {createPrivateKey} from 'node:crypto';

// Pure comparison: never echoes keys, tokens, account email or file contents.
export function verifyFirebaseIdentity(android,account) {
 const project=android?.project_info?.project_id;
 if(typeof project!=='string'||!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(project)||project==='hunkart-staging')throw Error('Invalid production Android Firebase project');
 const packages=new Set((Array.isArray(android.client)?android.client:[]).map(c=>c?.client_info?.android_client_info?.package_name));
 if(!['com.hunkart.shopkeeper','com.hunkart.deliverypartner'].every(p=>packages.has(p)))throw Error('Both production staff package IDs required');
 if(account?.project_id!==project||account?.type!=='service_account'||account?.token_uri!=='https://oauth2.googleapis.com/token'||
 typeof account.client_email!=='string'||!account.client_email.endsWith('@'+project+'.iam.gserviceaccount.com'))throw Error('Firebase Android/server identity mismatch');
 let key;
 try{key=createPrivateKey(account.private_key);}catch{throw Error('Invalid Firebase server private key');}
 if(key.asymmetricKeyType!=='rsa'||(key.asymmetricKeyDetails?.modulusLength||0)<2048)throw Error('Firebase server RSA key required');
 return {projectId:project,staffPackagesMatched:true,serverKeyParsed:true};
}
