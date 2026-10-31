import assert from 'node:assert/strict';
import {deploymentPackage,packageManifest} from './package.mjs';
const pkg=deploymentPackage(),manifest=packageManifest(pkg);
assert.equal(pkg.name,'dispatch-staff-worker');assert.equal(pkg.entrypoint_path,'index.ts');
assert.equal(pkg.verify_jwt,false);assert.equal(pkg.files.length,7);
assert.deepEqual(manifest,packageManifest(deploymentPackage()));
for(const file of pkg.files){
 assert.ok(!file.name.includes('/'));assert.ok(file.content.length>100);
 assert.ok(!/from\s+['"]\.\.\//.test(file.content));
 assert.ok(!file.content.includes('jjitqihblpubqwbggjpv'));
}
assert.ok(pkg.files.find(f=>f.name==='config.mjs').content.includes("get('FCM_PROJECT_ID')"));
assert.ok(pkg.files.find(f=>f.name==='config.mjs').content.includes("PRODUCTION_FIREBASE_PROJECT='hunkart-production'"));
assert.ok(!pkg.files.some(f=>/json$|sql$|test|fixture|keystore|google-services/.test(f.name)));
assert.ok(pkg.files.find(f=>f.name==='index.ts').content.includes("from './batch-core.mjs'"));
assert.ok(pkg.files.find(f=>f.name==='send.mjs').content.includes("from './fcm-core.mjs'"));
console.log('PASS: 38 deterministic source-package checks; no deployment or secret access');
