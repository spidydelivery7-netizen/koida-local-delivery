package com.hunkart.staff.staging;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.JavascriptInterface;
import com.google.firebase.messaging.FirebaseMessaging;

public class MainActivity extends Activity {
 private WebView web;
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
  web=new WebView(this);setContentView(web);
  web.addJavascriptInterface(new TokenBridge(),"HunkartNative");
  WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);settings.setDomStorageEnabled(true);settings.setAllowFileAccess(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
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
 @Override protected void onResume(){super.onResume();if(web!=null)deliverToken();}
 @Override public void onBackPressed(){if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();}
}
