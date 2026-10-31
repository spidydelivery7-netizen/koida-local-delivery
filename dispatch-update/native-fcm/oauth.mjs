// Server-side only. Store the service account JSON in a staging Edge secret.
const encode = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const enc = value => encode(new TextEncoder().encode(JSON.stringify(value)));
export async function firebaseAccessToken(serviceAccount, fetchImpl=fetch, now=Date.now()) {
 const {client_email,private_key,token_uri} = serviceAccount || {};
 if (!client_email || !private_key || token_uri !== 'https://oauth2.googleapis.com/token') throw Error('Invalid FCM service account');
 const raw=Uint8Array.from(atob(private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,'')),x=>x.charCodeAt(0));
 const key=await crypto.subtle.importKey('pkcs8',raw,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
 const seconds=Math.floor(now/1000), unsigned=enc({alg:'RS256',typ:'JWT'})+'.'+enc({iss:client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:token_uri,iat:seconds,exp:seconds+3000});
 const signature=encode(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(unsigned))));
 const response=await fetchImpl(token_uri,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:unsigned+'.'+signature})});
 if (!response.ok) throw Error('FCM token exchange failed');
 const result=await response.json();
 if (typeof result.access_token!=='string' || !result.access_token) throw Error('FCM access token missing');
 return result.access_token;
}
