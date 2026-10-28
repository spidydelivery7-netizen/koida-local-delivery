const assert=require('node:assert/strict');const vm=require('node:vm');const fs=require('node:fs');const path=require('node:path');const root=path.join(__dirname,'..');
let count=0;
(async()=>{
 const shop=fs.readFileSync(path.join(root,'shopkeeper.html'),'utf8');const fn=shop.slice(shop.indexOf('async function decideShopOrder('),shop.indexOf('async function loadShopOrders('));
 const calls=[],messages=[];let reloads=0;let reply={data:{ok:true}};
 const context=vm.createContext({notifyStoredOrder:async()=>({ok:true}),cfg:{supabaseUrl:"fixture"},confirm:()=>true,setStatus:s=>messages.push(s),loadShopOrders:async()=>reloads++,sb:{rpc:async(...args)=>{calls.push(args);return reply;}}});vm.runInContext(fn,context);
 function card(){const controls=[{disabled:false},{disabled:false}];return {dataset:{},controls,querySelectorAll:()=>controls};}
 let c=card();context.o={order_id:'order-fixture'};context.c=c;
 await vm.runInContext('decideShopOrder(o,true,"",c)',context);assert.equal(calls[0][0],'hd_accept_shop_order');assert.equal(calls[0][1].p_order_id,'order-fixture');assert.equal(reloads,1);count++;
 c=card();context.c=c;await vm.runInContext('decideShopOrder(o,false,"",c)',context);assert.equal(calls.length,1);count++;
 reply={error:{message:'Order is cancelled'}};c=card();context.c=c;await vm.runInContext('decideShopOrder(o,true,"",c)',context);assert.equal(c.dataset.saving,undefined);assert.ok(c.controls.every(x=>!x.disabled));assert.equal(reloads,1);assert.match(messages.at(-1),/cancelled/);count++;
 reply={data:{ok:true,refund_status:'queued'}};c=card();context.c=c;await vm.runInContext('decideShopOrder(o,false,"Item unavailable",c)',context);assert.equal(calls.at(-1)[0],'hd_reject_shop_order');assert.equal(calls.at(-1)[1].p_reason,'Item unavailable');assert.match(messages.at(-1),/not yet confirmed/);count++;
 const riders=fs.readFileSync(path.join(__dirname,'rider-controls.js'),'utf8');const elements=new Map();const elem=id=>{if(!elements.has(id))elements.set(id,{textContent:'',replaceChildren(){},append(){},querySelectorAll(){return[];}});return elements.get(id)};
 const rpc=[];let resolveGps;const gps=new Promise(resolve=>resolveGps=resolve);
 const ctx=vm.createContext({$:elem,profile:{id:'rider'},document:{hidden:false,addEventListener(){}},currentPosition:()=>gps,sb:{rpc:async(n,p)=>{rpc.push([n,p]);return {data:{ok:true}};}},clearInterval(){},setInterval(){return 1;},setStatus(){},loadDeliveries:async()=>{}});
 vm.runInContext(riders,ctx);vm.runInContext('dispatchWantedOnline=true',ctx);const flight=vm.runInContext('dispatchPresence()',ctx);const off=vm.runInContext('dispatchOffline()',ctx);resolveGps({coords:{latitude:21,longitude:85}});await flight;await off;
 assert.equal(rpc.length,1);assert.equal(rpc[0][1].p_online,false);assert.match(elem('dispatchPresence').textContent,/Offline/);count++;
 const admin=fs.readFileSync(path.join(root,'admin.html'),'utf8');assert.ok(!admin.includes('class="green confirmOrder"'));assert.ok(!admin.includes('const confirmButton='));count++;
 assert.equal(fs.readFileSync(path.join(root,'shopkeeper-app/index.html'),'utf8'),shop);count++;
 const delivery=fs.readFileSync(path.join(root,'delivery-app/index.html'),'utf8');assert.ok(delivery.includes('&& o.order_status === "packed"'));assert.ok(delivery.includes('"hd_my_deliveries"'));count++;
 console.log(count+' UI/unit preservation checks passed. Not browser or database E2E tests.');
})().catch(e=>{console.error(e);process.exit(1)});
