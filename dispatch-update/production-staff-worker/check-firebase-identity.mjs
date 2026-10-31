import {readFileSync} from 'node:fs';
import {verifyFirebaseIdentity} from './firebase-identity.mjs';
// Run only in a trusted private workspace. Inputs must never be committed.
try{
 const [androidPath,serverPath]=process.argv.slice(2);
 if(!androidPath||!serverPath||process.argv.length!==4)throw Error('Expected two private configuration paths');
 const result=verifyFirebaseIdentity(JSON.parse(readFileSync(androidPath,'utf8')),JSON.parse(readFileSync(serverPath,'utf8')));
 console.log(JSON.stringify(result));
}catch{
 // No source values, paths, stack traces or underlying parsing errors in logs.
 console.error('Firebase identity check failed; inspect inputs privately.');process.exitCode=1;
}
