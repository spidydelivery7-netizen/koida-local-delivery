package com.hunkart.staff.staging;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.webkit.WebResourceRequest;
import android.widget.FrameLayout;
import android.view.WindowInsets;
import android.graphics.Insets;
import android.webkit.WebChromeClient;
import android.webkit.GeolocationPermissions;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.JavascriptInterface;
import com.google.firebase.messaging.FirebaseMessaging;

public class MainActivity extends Activity {
 private WebView web;
 private GeolocationPermissions.Callback pendingLocation;
 private String pendingLocationOrigin;
 private static final String ORIGIN=BuildConfig.BASE_URL;
 private boolean trustedPage(){
  if(web==null || web.getUrl()==null)return false;
  Uri current=Uri.parse(web.getUrl()),base=Uri.parse(ORIGIN);
  return "https".equals(current.getScheme()) && base.getAuthority().equals(current.getAuthority())
   && current.getPath()!=null && current.getPath().startsWith(BuildConfig.PAGE_PATH);
 }
 public class TokenBridge {
  @JavascriptInterface public void requestToken(){runOnUiThread(()->deliverToken());}
 }
 private void deliverToken(){
  FirebaseMessaging.getInstance().getToken().addOnSuccessListener(token->{
   if(!trustedPage())return;
   String quoted=org.json.JSONObject.quote(token);
   web.evaluateJavascript("window.dispatchEvent(new CustomEvent('hunkart-native-token',{detail:{token:"+quoted+"}}))",null);
  });
 }
 @Override public void onCreate(Bundle state){
  super.onCreate(state);
  if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)
   requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},42);
  web=new WebView(this);
  FrameLayout content=new FrameLayout(this);
  content.setBackgroundColor(0xff111827);
  content.addView(web,new FrameLayout.LayoutParams(-1,-1));
  setContentView(content);
  // Android 15 enforces edge-to-edge for target 35. Inset the WebView itself
  // so fixed HTML headers and bottom controls stay outside bars and cutouts.
  if(Build.VERSION.SDK_INT>=30){
   getWindow().setDecorFitsSystemWindows(false);
   content.setOnApplyWindowInsetsListener((view,insets)->{
    Insets safe=insets.getInsets(WindowInsets.Type.systemBars()
     | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
    FrameLayout.LayoutParams layout=(FrameLayout.LayoutParams)web.getLayoutParams();
    layout.setMargins(safe.left,safe.top,safe.right,safe.bottom);
    web.setLayoutParams(layout);
    return WindowInsets.CONSUMED;
   });
   content.requestApplyInsets();
  }
  web.addJavascriptInterface(new TokenBridge(),"HunkartNative");
  WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);settings.setDomStorageEnabled(true);settings.setAllowFileAccess(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
  web.setWebChromeClient(new WebChromeClient(){
   @Override public void onGeolocationPermissionsShowPrompt(String origin,GeolocationPermissions.Callback callback){
    Uri allowed=Uri.parse(ORIGIN),requested=Uri.parse(origin);
    if(!trustedPage() || !"https".equals(requested.getScheme()) || !allowed.getAuthority().equals(requested.getAuthority())){
     callback.invoke(origin,false,false);return;
    }
    if(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED
       || checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)==PackageManager.PERMISSION_GRANTED){
     callback.invoke(origin,true,false);return;
    }
    pendingLocation=callback;pendingLocationOrigin=origin;
    requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION},43);
   }
  });
  web.setWebViewClient(new WebViewClient(){
   @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
    Uri uri=request.getUrl();
    Uri base=Uri.parse(ORIGIN);
    if("https".equals(uri.getScheme()) && base.getAuthority().equals(uri.getAuthority())
      && uri.getPath()!=null && uri.getPath().startsWith(BuildConfig.PAGE_PATH))return false;
    startActivity(new Intent(Intent.ACTION_VIEW,uri));return true;
   }
   @Override public void onPageFinished(WebView view,String url){if(trustedPage())deliverToken();}
  });
  web.loadUrl(ORIGIN+BuildConfig.PAGE_PATH);
 }
 @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] grantResults){
  super.onRequestPermissionsResult(requestCode,permissions,grantResults);
  if(requestCode==43 && pendingLocation!=null){
   boolean granted=false;
   for(int result:grantResults)if(result==PackageManager.PERMISSION_GRANTED)granted=true;
   pendingLocation.invoke(pendingLocationOrigin,granted&&trustedPage(),false);
   pendingLocation=null;pendingLocationOrigin=null;
  }
 }
 @Override protected void onResume(){super.onResume();if(web!=null)deliverToken();}
 @Override public void onBackPressed(){if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();}
}
