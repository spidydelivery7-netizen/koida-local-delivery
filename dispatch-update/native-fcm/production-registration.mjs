// Production staff pages only. Authorization stays in the database RPCs.
const URL='https://amnqqxgmqciipcortpmi.supabase.co';
export function attachNativeStaffRegistration({sb,role,supabaseUrl,host=window}) {
 const path=role==='shopkeeper'?'/shopkeeper-app/':role==='delivery_boy'?'/delivery-app/':null;
 if(supabaseUrl!==URL||!path||host.location?.origin!=='https://hunkart.com'||
    !host.location.pathname.startsWith(path)||!host.HunkartNative?.requestToken)return ()=>{};
 let token=null,registered=null,active=true,stopping=false,tail=Promise.resolve();
 const pendingRemoval=new Set();
 const report=state=>host.dispatchEvent(new host.CustomEvent('hunkart-native-status',{detail:{state}}));
 const enqueue=task=>{const next=tail.then(task);tail=next.catch(()=>{});return next;};
 async function save(){
  if(!active||stopping||!token)return;
  const current=token;
  const {data,error}=await sb.auth.getSession();
  if(error)throw error;
  const user=data?.session?.user?.id;
  if(!user||!active||stopping)return;
  if(registered?.user===user&&registered.token===current&&pendingRemoval.size===0)return;
  const result=await sb.rpc('hd_save_native_device',{p_role:role,p_token:current});
  if(result.error||result.data!==true)throw new Error('Native registration not confirmed');
  const previous=registered;
  registered={user,token:current};
  if(previous?.user===user&&previous.token!==current)pendingRemoval.add(previous.token);
  for(const old of pendingRemoval){
   if(old===current){pendingRemoval.delete(old);continue;}
   const removed=await sb.rpc('hd_remove_native_device',{p_token:old});
   if(removed.error)throw new Error('Previous native token removal failed');
   pendingRemoval.delete(old);
  }
  if(active&&!stopping)report('registered');
 }
 const refresh=()=>enqueue(save).catch(()=>report('unavailable'));
 function onToken(event){
  const next=event?.detail?.token;
  if(typeof next!=='string'||next.length<20||next.length>4096||/\s/.test(next))return;
  token=next;refresh();
 }
 host.addEventListener('hunkart-native-token',onToken);
 const {data:{subscription}}=sb.auth.onAuthStateChange(event=>{
  if(event==='SIGNED_OUT'){registered=null;report('signed-out');}
  else host.setTimeout(refresh,0);
 });
 const originalSignOut=sb.auth.signOut;
 const wrappedSignOut=async (...args)=>{
  stopping=true;
  try{
   await enqueue(async()=>{
    for(const value of new Set([...pendingRemoval,registered?.token,token].filter(Boolean))){
     const result=await sb.rpc('hd_remove_native_device',{p_token:value});
     if(result.error)throw new Error('Notification logout cleanup failed. Retry logout when online.');
    }
   });
   const result=await originalSignOut.apply(sb.auth,args);
   if(!result?.error)registered=null;
   return result;
  }catch(error){report('logout-failed');throw error;}
  finally{stopping=false;}
 };
 sb.auth.signOut=wrappedSignOut;
 host.HunkartNative.requestToken();
 return ()=>{active=false;host.removeEventListener('hunkart-native-token',onToken);subscription.unsubscribe();if(sb.auth.signOut===wrappedSignOut)sb.auth.signOut=originalSignOut;};
}
