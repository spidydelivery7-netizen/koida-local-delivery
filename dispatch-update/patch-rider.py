from pathlib import Path
r=Path(__file__).resolve().parent.parent;p=r/'delivery-app/index.html';s=p.read_text()
a='    <div id="gpsNotice"';i=s.index(a);s=s[:i]+'''    <section class="panel" aria-label="Delivery availability">
      <button id="dispatchToggle" type="button">Go online</button>
      <p id="dispatchPresence" class="small" aria-live="polite">Offline · Go online with current GPS to receive requests. Keep the app open; background delivery alerts are not guaranteed.</p>
      <div id="dispatchOffers"></div>
    </section>

'''+s[i:]
assert '"get_my_deliveries_v2"' in s;s=s.replace('"get_my_deliveries_v2"','"hd_my_deliveries"')
a='''const canStart =
      o.delivery_status === "assigned" ||
      o.delivery_status === "picked_up";'''
b='''const canStart =
      (o.delivery_status === "assigned" || o.delivery_status === "picked_up") && o.order_status === "packed";'''
assert a in s;s=s.replace(a,b)
a='''async () => {

  stopGps();

  await sb.auth.signOut();''';b='''async () => {
  try{await dispatchOffline();}catch(e){setStatus("Could not confirm offline status. Presence will expire automatically. "+e.message);}
  stopGps();

  await sb.auth.signOut();'''
assert a in s;s=s.replace(a,b)
a='\nboot();';assert a in s;s=s.replace(a,'\n'+(r/'dispatch-update/rider-controls.js').read_text()+'\nboot();')
p.write_text(s)
p=r/'delivery-app/sw.js';s=p.read_text().replace('hunkart-delivery-v3','hunkart-delivery-dispatch-v4');p.write_text(s)
p=r/'shopkeeper-app/sw.js';s=p.read_text();s=s.replace('const CACHE_NAME = ', 'const CACHE_NAME = ')
# Change only the cache identifier, preserving request handling.
import re
s=re.sub(r'(const CACHE_NAME\s*=\s*["\x27])([^"\x27]+)',lambda m:m[1]+m[2]+'-dispatch-v1',s,count=1);p.write_text(s)
