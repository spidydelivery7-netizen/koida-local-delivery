self.addEventListener("install",()=>self.skipWaiting());

self.addEventListener("activate",event=>{
  event.waitUntil(self.clients.claim());
});

self.addEventListener("push",event=>{
  let data={
    title:"HUNKART Ride",
    body:"A nearby ride request is available.",
    url:"./"
  };

  try{
    data=event.data.json();
  }catch(e){}

  event.waitUntil(
    self.registration.showNotification(
      data.title||"HUNKART Ride",
      {
        body:data.body||"A nearby ride request is available.",
        icon:"../icons/icon-192.png",
        data:data.url||"./"
      }
    )
  );
});

self.addEventListener("notificationclick",event=>{
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data||"./"));
});
