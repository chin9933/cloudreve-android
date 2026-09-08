package com.example.cloudreve;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.drawable.ColorDrawable;
import android.os.Bundle;
import android.media.AudioManager;
import android.provider.Settings;
import android.view.WindowManager;
import java.util.HashMap;
import java.util.Map;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private String videoSession;
    private float originalBrightness = -1f;
    private int originalVolumeStream;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Match the locally saved Flutter preference while its first frame loads.
        String mode = "auto";
        try {
            mode = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    .getString("flutter.settings.dark_mode", "auto");
        } catch (ClassCastException ignored) {
            // Recover from a corrupt local preference instead of crashing at launch.
        }
        boolean dark = "open".equals(mode) || (!"close".equals(mode)
                && (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES);
        getWindow().setBackgroundDrawable(new ColorDrawable(dark ? 0xFF0D1422 : 0xFFF4F7FC));
    }

    @Override
    public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "cloudreve/video_device").setMethodCallHandler(this::handleVideoDevice);
    }

    private void handleVideoDevice(MethodCall call, MethodChannel.Result result) {
        try {
            String session = call.argument("session");
            if (session == null) {
                result.error("invalid_session", "Missing video session", null);
                return;
            }
            if ("begin".equals(call.method)) {
                if (!session.equals(videoSession)) {
                    restoreVideoWindow();
                    originalBrightness = getWindow().getAttributes().screenBrightness;
                    originalVolumeStream = getVolumeControlStream();
                    videoSession = session;
                    setVolumeControlStream(AudioManager.STREAM_MUSIC);
                }
                result.success(null);
                return;
            }
            if ("end".equals(call.method)) {
                // An older route may finish disposing after a new one opens.
                if (session.equals(videoSession)) restoreVideoWindow();
                result.success(null);
                return;
            }
            if (!session.equals(videoSession)) {
                result.error("expired_session", "Video session has ended", null);
                return;
            }
            AudioManager audio = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            int maximum = Math.max(1, audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC));
            switch (call.method) {
                case "read":
                    float brightness = getWindow().getAttributes().screenBrightness;
                    if (brightness < 0) {
                        brightness = Settings.System.getInt(getContentResolver(),
                                Settings.System.SCREEN_BRIGHTNESS, 128) / 255f;
                    }
                    Map<String, Object> levels = new HashMap<>();
                    levels.put("brightness", (double) Math.max(.05f, Math.min(1f, brightness)));
                    levels.put("volume", audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                            / (double) maximum);
                    result.success(levels);
                    break;
                case "brightness":
                    double light = readLevel(call, .05);
                    WindowManager.LayoutParams attributes = getWindow().getAttributes();
                    attributes.screenBrightness = (float) light;
                    getWindow().setAttributes(attributes);
                    result.success(light);
                    break;
                case "volume":
                    double volume = readLevel(call, 0);
                    // Flags=0 avoids a second Android popup above the app's own HUD.
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC,
                            (int) Math.round(volume * maximum), 0);
                    result.success(audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                            / (double) maximum);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Exception exception) {
            result.error("device_control_failed", "Unable to adjust video device controls", null);
        }
    }

    private double readLevel(MethodCall call, double minimum) {
        Number value = call.argument("value");
        if (value == null || !Double.isFinite(value.doubleValue())) {
            throw new IllegalArgumentException("Invalid device level");
        }
        return Math.max(minimum, Math.min(1, value.doubleValue()));
    }

    private void restoreVideoWindow() {
        if (videoSession == null) return;
        WindowManager.LayoutParams attributes = getWindow().getAttributes();
        attributes.screenBrightness = originalBrightness;
        getWindow().setAttributes(attributes);
        setVolumeControlStream(originalVolumeStream);
        videoSession = null;
    }

    @Override
    protected void onDestroy() {
        restoreVideoWindow();
        super.onDestroy();
    }
}
