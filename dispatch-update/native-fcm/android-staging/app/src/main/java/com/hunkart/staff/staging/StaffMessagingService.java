package com.hunkart.staff.staging;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.content.Intent;
import android.os.Build;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.time.Instant;
import java.util.Map;

public class StaffMessagingService extends FirebaseMessagingService {
 private static final String CHANNEL="hunkart_staff_staging_alert_2";
 private static final long[] VIBRATION={0,800,300,800,300,800,300,800};
 @Override public void onNewToken(String token){super.onNewToken(token);}
 @Override public void onMessageReceived(RemoteMessage message){
  Map<String,String> data=message.getData();
  String event=data.get("kind");
  if(!"rider_offer".equals(event)&&!"shop_order_ready".equals(event))return;
  if("rider_offer".equals(event) != "/delivery-app/".equals(BuildConfig.PAGE_PATH))return;
  try {if(Instant.parse(data.get("expiresAt")).toEpochMilli()<=System.currentTimeMillis())return;}catch(Exception e){return;}
  NotificationManager manager=getSystemService(NotificationManager.class);
  Uri sound=RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
  if(sound==null)sound=RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
  if(Build.VERSION.SDK_INT>=26){
   NotificationChannel channel=new NotificationChannel(CHANNEL,"HUNKART order alerts (staging)",NotificationManager.IMPORTANCE_HIGH);
   channel.enableVibration(true);channel.setVibrationPattern(VIBRATION);
   channel.setSound(sound,new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build());
   manager.createNotificationChannel(channel);
  }
  Intent open=new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
  PendingIntent pending=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
  Notification.Builder builder=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,CHANNEL):new Notification.Builder(this);
  if(Build.VERSION.SDK_INT<26)builder.setPriority(Notification.PRIORITY_HIGH).setVibrate(VIBRATION).setSound(sound);
  Notification notification=builder.setSmallIcon(android.R.drawable.ic_dialog_info)
   .setContentTitle("rider_offer".equals(event)?"HUNKART delivery offer":"HUNKART new order")
   .setContentText("Open the app to review before it expires.").setAutoCancel(true).setContentIntent(pending)
   .setTimeoutAfter(30000).build();
  notification.flags |= Notification.FLAG_INSISTENT;
  manager.notify((data.get("orderId")+":"+data.get("offerId")).hashCode(),notification);
 }
}
