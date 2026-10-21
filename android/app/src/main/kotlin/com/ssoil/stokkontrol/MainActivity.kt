package com.ssoil.stokkontrol

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
 override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
  super.configureFlutterEngine(flutterEngine)
  MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"ssoil.popis/bridge").setMethodCallHandler { call,result ->
   when(call.method) {
    "accessibilitySettings" -> {startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));result.success(null)}
    "armPopis" -> {
      getSharedPreferences("popis_bridge",MODE_PRIVATE).edit()
        .putBoolean("armed",true).remove("raw_text").commit()
      val intent=packageManager.getLaunchIntentForPackage("com.mladost.cadmus")
      if(intent!=null){
        intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        startActivity(intent)
        result.success(null)
      } else {
        getSharedPreferences("popis_bridge",MODE_PRIVATE).edit().putBoolean("armed",false).apply()
        result.error("NO_APP","Cadmus bulunamadı",null)
      }
    }
    "readPopis" -> result.success(getSharedPreferences("popis_bridge",MODE_PRIVATE).getString("raw_text",null))
    "returnPopis" -> {
      val intent=packageManager.getLaunchIntentForPackage("com.mladost.cadmus")
      if(intent!=null){
        intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        startActivity(intent)
        result.success(null)
      } else result.error("NO_APP","cadmus (com.mladost.cadmus) bulunamadı",null)
    }
    else -> result.notImplemented()
   }
  }
 }
}
