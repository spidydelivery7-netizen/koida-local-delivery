package com.hunkart.staff.staging;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.time.Instant;
import java.util.Map;

public class StaffMessagingService extends FirebaseMessagingService {
 private static final String CHANNEL="hunkart_staff_staging_1";
 @Override public void onNewToken(String token){super.onNewToken(token);}
 @Override public void onMessageReceived(RemoteMessage message){
  Map<String,String> data=message.getData();
  String event=data.get("kind");
  if(!"rider_offer".equals(event)&&!"shop_order_ready".equals(event))return;
  if("rider_offer".equals(event) != "/delivery-app/".equals(BuildConfig.PAGE_PATH))return;
  try {if(Instant.parse(data.get("expiresAt")).toEpochMilli()<=System.currentTimeMillis())return;}catch(Exception e){return;}
  NotificationManager manager=getSystemService(NotificationManager.class);
  if(Build.VERSION.SDK_INT>=26){
   NotificationChannel channel=new NotificationChannel(CHANNEL,"HUNKART order alerts (staging)",NotificationManager.IMPORTANCE_HIGH);
   channel.enableVibration(true);channel.setVibrationPattern(new long[]{0,500,200,500,200,500});manager.createNotificationChannel(channel);
  }
  Intent open=new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
  PendingIntent pending=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
  Notification.Builder builder=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,CHANNEL):new Notification.Builder(this);
  if(Build.VERSION.SDK_INT<26)builder.setPriority(Notification.PRIORITY_HIGH).setVibrate(new long[]{0,500,200,500,200,500})
   .setDefaults(Notification.DEFAULT_SOUND);
  Notification notification=builder.setSmallIcon(android.R.drawable.ic_dialog_info)
   .setContentTitle("rider_offer".equals(event)?"HUNKART delivery offer":"HUNKART new order")
   .setContentText("Open the app to review before it expires.").setAutoCancel(true).setContentIntent(pending).build();
  manager.notify((data.get("orderId")+":"+data.get("offerId")).hashCode(),notification);
 }
}
