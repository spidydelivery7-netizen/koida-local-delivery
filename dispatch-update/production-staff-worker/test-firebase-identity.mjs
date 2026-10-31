import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {verifyFirebaseIdentity} from './firebase-identity.mjs';
const {privateKey}=generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{type:'pkcs8',format:'pem'},publicKeyEncoding:{type:'spki',format:'pem'}});
const android={project_info:{project_id:'hunkart-fixture'},client:['com.hunkart.shopkeeper','com.hunkart.deliverypartner'].map(package_name=>({client_info:{android_client_info:{package_name}}}))};
const server={type:'service_account',project_id:'hunkart-fixture',client_email:'worker@hunkart-fixture.iam.gserviceaccount.com',token_uri:'https://oauth2.googleapis.com/token',private_key:privateKey};
assert.deepEqual(verifyFirebaseIdentity(android,server),{projectId:'hunkart-fixture',staffPackagesMatched:true,serverKeyParsed:true});
let checks=1;
for(const [a,s] of [
 [null,server],[{...android,project_info:{project_id:'hunkart-staging'}},server],
 [{...android,client:android.client.slice(0,1)},server],
 [{...android,client:[{client_info:{android_client_info:{package_name:'com.hunkart.shopkeeper.staging'}}}]},server],
 [android,{...server,project_id:'wrong-project'}],[android,{...server,type:'authorized_user'}],
 [android,{...server,token_uri:'https://evil.test/token'}],[android,{...server,client_email:'wrong@evil.test'}],
 [android,{...server,private_key:'invalid'}],
 [android,{...server,private_key:generateKeyPairSync('ec',{namedCurve:'prime256v1',privateKeyEncoding:{type:'pkcs8',format:'pem'},publicKeyEncoding:{type:'spki',format:'pem'}}).privateKey}]
]){assert.throws(()=>verifyFirebaseIdentity(a,s));checks++;}
console.log('PASS: '+checks+' Firebase identity checks with generated fixture key; no real credentials read');
