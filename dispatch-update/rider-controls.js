// Included inside the existing delivery page module; uses its sb/profile/currentPosition.
let dispatchWantedOnline=false,dispatchBusy=false,dispatchPollBusy=false;
let dispatchPresenceFlight=null,dispatchTimer=null;
async function dispatchPresence(){
  if(dispatchPresenceFlight)return dispatchPresenceFlight;
  dispatchPresenceFlight=(async()=>{
    if(!profile||!dispatchWantedOnline)return;
    const pos=await currentPosition();
    if(!dispatchWantedOnline||!profile)return;
    const {data,error}=await sb.rpc('hd_heartbeat',{p_online:true,p_lat:pos.coords.latitude,p_lng:pos.coords.longitude});
    if(error||!data?.ok)throw error||new Error('Online status not confirmed');
    if(dispatchWantedOnline)$('dispatchPresence').textContent='Online · Keep this screen open for delivery requests.';
  })();
  try{await dispatchPresenceFlight;}finally{dispatchPresenceFlight=null;}
}
async function dispatchOffline(){
  dispatchWantedOnline=false;
  if(dispatchTimer){clearInterval(dispatchTimer);dispatchTimer=null;}
  try{await dispatchPresenceFlight;}catch(_){}
  if(sb&&profile){const {error}=await sb.rpc('hd_heartbeat',{p_online:false,p_lat:null,p_lng:null});if(error)throw error;}
  $('dispatchPresence').textContent='Offline · No new delivery requests';
  $('dispatchToggle').textContent='Go online';
  $('dispatchOffers').replaceChildren();
}
async function dispatchRefresh(){
  if(!profile||!dispatchWantedOnline||dispatchPollBusy||document.hidden)return;
  dispatchPollBusy=true;
  try{
    const {data,error}=await sb.rpc('hd_my_offers');if(error)throw error;
    if(!dispatchWantedOnline)return;
    const box=$('dispatchOffers');box.replaceChildren();
    for(const f of data||[]){
      const card=document.createElement('div');card.className='panel';
      const title=document.createElement('b');title.textContent='New delivery request · '+f.order_number;card.append(title);
      const detail=document.createElement('p');detail.textContent='Pickup: '+f.shop_name+' · Shop to customer: '+(f.distance_km==null?'not available':Number(f.distance_km).toFixed(1)+' km');card.append(detail);
      const left=Math.max(0,Math.floor((Date.parse(f.expires_at)-Date.parse(f.server_now))/1000));
      const expiry=document.createElement('p');expiry.className='small';expiry.textContent='Request expires in about '+left+' seconds. Customer contact appears after acceptance.';card.append(expiry);
      for(const [label,value]of [['Accept delivery',true],['Decline',false]]){
        const b=document.createElement('button');b.textContent=label;b.className=value?'':'gray';b.disabled=dispatchBusy;
        b.onclick=async()=>{
          if(dispatchBusy)return;dispatchBusy=true;box.querySelectorAll('button').forEach(x=>x.disabled=true);
          try{const {data,error}=await sb.rpc('hd_respond_offer',{p_offer_id:f.id,p_accept:value});if(error||!data?.ok)throw error||new Error('Response not confirmed');setStatus(value?'Delivery accepted. Wait for the shop to mark Packed before collecting.':'Request declined.');await loadDeliveries();}
          catch(e){setStatus('Request response: '+e.message);}
          finally{dispatchBusy=false;await dispatchRefresh();}
        };card.append(b);
      }
      box.append(card);
    }
  }catch(e){$('dispatchPresence').textContent='Requests unavailable: '+e.message;}
  finally{dispatchPollBusy=false;}
}
$('dispatchToggle').onclick=async()=>{
  const button=$('dispatchToggle');button.disabled=true;
  try{
    if(dispatchWantedOnline){await dispatchOffline();}
    else{
      dispatchWantedOnline=true;await dispatchPresence();
      button.textContent='Go offline';await dispatchRefresh();
      let polls=0;
      dispatchTimer=setInterval(()=>{if(!profile||document.hidden)return;dispatchRefresh();if(++polls%6===0)dispatchPresence().catch(e=>{$('dispatchPresence').textContent='GPS refresh failed; requests will stop without fresh location. '+e.message;});if(polls%3===0)loadDeliveries().catch(e=>setStatus('Delivery refresh: '+e.message));},5000);
    }
  }catch(e){try{await dispatchOffline();}catch(_){}setStatus('Online status: '+e.message);}
  finally{button.disabled=false;}
};
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&dispatchWantedOnline){dispatchPresence().then(dispatchRefresh).catch(e=>setStatus('Go online again: '+e.message));}});
