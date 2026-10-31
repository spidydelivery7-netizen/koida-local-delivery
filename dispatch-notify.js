// Sends only a stored notification intent for an authorized order. Never a
// caller-supplied customer, title, endpoint or message.
export async function notifyStoredOrder({sb,supabaseUrl,orderId}){
 try{
  const {data:{session},error}=await sb.auth.getSession();
  if(error||!session?.access_token)return {ok:false};
  const response=await fetch(supabaseUrl+'/functions/v1/dispatch-notification-worker',{
   method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+session.access_token},body:JSON.stringify({order_id:orderId})
  });
  const result=await response.json();
  return {ok:response.ok&&result.pending===0,sent:Number(result.sent||0)};
 }catch{return {ok:false};}
}
