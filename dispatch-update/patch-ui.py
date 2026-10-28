from pathlib import Path
r=Path(__file__).resolve().parent.parent
p=r/'shopkeeper.html';s=p.read_text()
a='new:{badge:"NEW ORDER",badgeClass:"new",button:"Start Packing",buttonClass:"startBtn",next:"preparing",note:confirmed?"Admin confirmed. Start preparing this order.":"Waiting for Admin confirmation."},'
b='new:{badge:"NEW ORDER",badgeClass:"new",button:confirmed?"Start Packing":"Accept Order",buttonClass:"startBtn",next:confirmed?"preparing":"accept",note:confirmed?"Order accepted. Start preparing this order.":"Accept only if your shop can fulfil this paid order."},'
assert a in s;s=s.replace(a,b)
a='<div class="stageNote">${stage.note}</div>`;'
b='''${o.order_status==="new"?'<label>Cannot fulfil this order?<select class="rejectReason"><option value="">Choose reason</option><option>Item unavailable</option><option>Shop cannot fulfil order</option></select></label><button type="button" class="rejectOrder red">Reject Order</button>':""}
      <div class="stageNote">${stage.note}</div>`;'''
assert a in s;s=s.replace(a,b)
a='if(stage.next==="packed")btn.onclick=()=>markOrderPacked(o,btn);';b='if(stage.next==="accept")btn.onclick=()=>decideShopOrder(o,true,"",card);\n      else '+a
assert a in s;s=s.replace(a,b)
a='    box.appendChild(card);\n  });\n}\n\nasync function loadShopOrders'
b='''    const reject=card.querySelector(".rejectOrder");
    if(reject)reject.onclick=()=>decideShopOrder(o,false,card.querySelector(".rejectReason").value,card);
    box.appendChild(card);
  });
}

async function decideShopOrder(order,accept,reason,card){
  if(card.dataset.saving==="yes")return;
  if(!accept&&!reason){setStatus("Choose a rejection reason first.");return;}
  if(!confirm(accept?"Accept this paid order for your shop?":"Reject this order and queue its remaining paid amount for refund?"))return;
  card.dataset.saving="yes";
  card.querySelectorAll("button,select").forEach(b=>b.disabled=true);
  try{
    const {data,error}=await sb.rpc(accept?"hd_accept_shop_order":"hd_reject_shop_order",accept?{p_order_id:order.order_id}:{p_order_id:order.order_id,p_reason:reason});
    if(error)throw error;
    if(!data?.ok)throw new Error("Order decision could not be confirmed. Refresh before retrying.");
    setStatus(accept?"Order accepted. Preparing can now start; delivery partner search is queued.":"Order rejected. Refund queued; it is not yet confirmed by the bank.");
    await loadShopOrders({alertNew:false});
  }catch(error){setStatus("Order decision failed: "+error.message);delete card.dataset.saving;card.querySelectorAll("button,select").forEach(b=>b.disabled=false);}
}

async function loadShopOrders'''
assert a in s;s=s.replace(a,b)
p.write_text(s);(r/'shopkeeper-app/index.html').write_text(s)
p=r/'admin.html';s=p.read_text();a='''${o.status==="new"
?`<button class="green confirmOrder">Confirm Order</button>
  <div class="small" style="align-self:center">After confirmation, Packing / Ready / Packed is controlled by the assigned shopkeeper.</div>`
:`<div class="small" style="align-self:center">Admin status action is complete. Shopkeeper manages Packing / Ready / Packed; delivery partner manages Out for Delivery.</div>`}'''
b='''<div class="small" style="align-self:center">${o.status==="new"?"Awaiting shopkeeper acceptance. Contact the shop if delayed.":"Shopkeeper controls Preparing / Ready / Packed. Partner accepts the delivery request."}</div>'''
assert a in s;s=s.replace(a,b)
a=s.index('const confirmButton=card.querySelector(".confirmOrder");');b=s.index('card.querySelector(\n".assignBtn"',a);s=s[:a]+s[b:]
# Queue information uses textContent and only the Admin RPC; no customer detail leak.
a='async function loadOrders(){';b='''async function loadDispatchQueue(){
  let box=document.getElementById("dispatchQueue");
  if(!box){box=document.createElement("div");box.id="dispatchQueue";box.className="card";document.getElementById("ordersList")?.before(box);}
  const {data,error}=await sb.rpc("hd_admin_queue");
  box.textContent=error?"Dispatch monitoring unavailable: "+error.message:(data?.length?data.map(x=>x.order_number+": "+x.state+" — "+x.note).join(" · "):"No dispatch exceptions or overdue shop responses.");
}
async function loadOrders(){
  loadDispatchQueue().catch(e=>setStatus("Dispatch monitoring: "+e.message));'''
assert a in s;s=s.replace(a,b);p.write_text(s)
