// Included by staging staff pages only; the Android shell dispatches the token event.
const STAGING_URL='https://jjitqihblpubqwbggjpv.supabase.co';
export function attachNativeStaffRegistration({sb,role,supabaseUrl,host=window}) {
 if(supabaseUrl!==STAGING_URL || !['shopkeeper','delivery_boy'].includes(role))return ()=>{};
 let token=null,registered=null,active=true;
 async function save(){
  if(!active||!token)return;
  const {data:{session},error}=await sb.auth.getSession();
  if(error||!session?.user)return;
  if(registered?.user===session.user.id&&registered.token===token)return;
  const result=await sb.rpc('hd_save_native_device',{p_role:role,p_token:token});
  if(result.error)throw result.error;
  registered={user:session.user.id,token};
 }
 function onToken(event){
  const next=event?.detail?.token;
  if(typeof next!=='string'||next.length<20||next.length>4096||/\s/.test(next))return;
  token=next;save().catch(e=>console.warn('Native device registration:',e));
 }
 host.addEventListener('hunkart-native-token',onToken);
 const {data:{subscription}}=sb.auth.onAuthStateChange((event)=>{
  if(event==='SIGNED_OUT')registered=null;
  else queueMicrotask(()=>save().catch(e=>console.warn('Native device registration:',e)));
 });
 const originalSignOut=sb.auth.signOut.bind(sb.auth);
 sb.auth.signOut=async (...args)=>{
  if(token){try{await sb.rpc('hd_remove_native_device',{p_token:token});}catch(e){console.warn('Native device removal:',e);}}
  registered=null;
  return originalSignOut(...args);
 };
 host.HunkartNative?.requestToken?.();
 return ()=>{active=false;host.removeEventListener('hunkart-native-token',onToken);subscription.unsubscribe();sb.auth.signOut=originalSignOut;};
}
