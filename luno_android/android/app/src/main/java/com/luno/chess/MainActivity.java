package com.luno.chess;

import android.content.pm.ApplicationInfo;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.ViewTreeObserver;
import android.view.Window;
import android.webkit.WebView;

import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    private static final String TAG = "LunoMainActivity";
    private static final long BOOT_PROBE_TIMEOUT_MS = 60_000L;
    private final Handler bootDiagnosticsHandler = new Handler(Looper.getMainLooper());
    private boolean deferredStartupPosted;
    private boolean bootWebReadyLogged;
    private boolean bootMenuReadyLogged;
    private boolean bootProbeFailureLogged;
    private long bootProbeDeadlineMs;
    private WebView bootWebView;

    private final Runnable bootWebProbe = new Runnable() {
        @Override
        public void run() {
            if (!BuildConfig.LUNO_BOOT_DIAGNOSTICS || bootWebView == null || isFinishing()) {
                return;
            }
            if (SystemClock.uptimeMillis() >= bootProbeDeadlineMs) {
                LunoBootDiagnostics.mark("LUNO_BOOT_WEB_PROBE_TIMEOUT");
                return;
            }
            String probe = "(function(){var m=document.getElementById('menu');"
                    + "var w=(document.readyState==='interactive'||document.readyState==='complete')"
                    + "&&typeof window.show==='function';"
                    + "return (w?'1':'0')+((m&&m.classList.contains('active'))?'1':'0');})()";
            try {
                bootWebView.evaluateJavascript(probe, value -> {
                    String state = value == null ? "" : value.replace("\"", "");
                    if (!bootWebReadyLogged && state.startsWith("1")) {
                        bootWebReadyLogged = true;
                        LunoBootDiagnostics.mark("LUNO_BOOT_11_WEB_READY");
                    }
                    if (!bootMenuReadyLogged && state.endsWith("1")) {
                        bootMenuReadyLogged = true;
                        LunoBootDiagnostics.mark("LUNO_BOOT_12_MENU_READY");
                    }
                    if (!bootWebReadyLogged || !bootMenuReadyLogged) {
                        bootDiagnosticsHandler.postDelayed(this, 250L);
                    }
                });
            } catch (Throwable error) {
                if (!bootProbeFailureLogged) {
                    bootProbeFailureLogged = true;
                    LunoBootDiagnostics.failure("LUNO_BOOT_WEB_PROBE_FAILED", error);
                }
                bootDiagnosticsHandler.postDelayed(this, 250L);
            }
        }
    };

    @Override
    public void onCreate(Bundle savedInstanceState) {
        LunoBootDiagnostics.mark("LUNO_BOOT_03_ACTIVITY_ENTER");
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        disableReleaseWebViewDebugging();
        LunoBootDiagnostics.mark("LUNO_BOOT_04_PLUGIN_REGISTRATION_BEGIN plugin=billing");
        try {
            registerPlugin(LunoBillingPlugin.class);
            LunoBootDiagnostics.mark("LUNO_BOOT_04_PLUGIN_REGISTRATION_END plugin=billing state=ready");
        } catch (Throwable error) {
            // The game must still open on devices without a usable Play Store.
            Log.e(TAG, "Billing plugin registration failed", error);
            LunoBootDiagnostics.failure(
                    "LUNO_BOOT_04_PLUGIN_REGISTRATION_END plugin=billing state=failed", error);
        }
        LunoBootDiagnostics.mark("LUNO_BOOT_04_PLUGIN_REGISTRATION_BEGIN plugin=app_check");
        try {
            registerPlugin(LunoAppCheckPlugin.class);
            LunoBootDiagnostics.mark("LUNO_BOOT_04_PLUGIN_REGISTRATION_END plugin=app_check state=ready");
        } catch (Throwable error) {
            Log.e(TAG, "App Check plugin registration failed", error);
            LunoBootDiagnostics.failure(
                    "LUNO_BOOT_04_PLUGIN_REGISTRATION_END plugin=app_check state=failed", error);
        }
        LunoBootDiagnostics.mark("LUNO_BOOT_04_PLUGIN_REGISTRATION");
        LunoBootDiagnostics.mark("LUNO_BOOT_05_SUPER_ONCREATE_BEGIN");
        super.onCreate(savedInstanceState);
        LunoBootDiagnostics.mark("LUNO_BOOT_06_SUPER_ONCREATE_END");
        startBootWebDiagnostics();
        postDeferredStartup();
    }

    @Override
    public void onDestroy() {
        bootDiagnosticsHandler.removeCallbacksAndMessages(null);
        bootWebView = null;
        super.onDestroy();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        // Diyalog/klavye sonrası odak geri gelince çubukları tekrar gizle (gerçek oyun hissi)
        if (hasFocus) {
            postDeferredStartup();
        }
    }

    private void disableReleaseWebViewDebugging() {
        if ((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            return;
        }
        try {
            WebView.setWebContentsDebuggingEnabled(false);
        } catch (Throwable error) {
            Log.w(TAG, "WebView debugging state could not be changed", error);
        }
    }

    private void postDeferredStartup() {
        if (deferredStartupPosted || getWindow() == null) {
            return;
        }
        deferredStartupPosted = true;
        getWindow().getDecorView().post(() -> {
            deferredStartupPosted = false;
            LunoBootDiagnostics.mark("LUNO_BOOT_SYSTEM_UI_BEGIN");
            applySystemUiSafely();
            LunoBootDiagnostics.mark("LUNO_BOOT_SYSTEM_UI_END");
            try {
                LunoAppCheckInitializer.initialize(this);
            } catch (Throwable error) {
                // Firebase/App Check is optional for drawing the first frame.
                Log.e(TAG, "Deferred App Check initialization failed", error);
            }
        });
    }

    private void startBootWebDiagnostics() {
        if (!BuildConfig.LUNO_BOOT_DIAGNOSTICS) {
            return;
        }
        try {
            bootWebView = getBridge() == null ? null : getBridge().getWebView();
            if (bootWebView == null) {
                LunoBootDiagnostics.mark("LUNO_BOOT_07_WEBVIEW_CREATED state=missing");
                return;
            }
            LunoBootDiagnostics.mark("LUNO_BOOT_07_WEBVIEW_CREATED");
            WebView diagnosticWebView = bootWebView;
            ViewTreeObserver observer = diagnosticWebView.getViewTreeObserver();
            observer.addOnDrawListener(new ViewTreeObserver.OnDrawListener() {
                private boolean recorded;

                @Override
                public void onDraw() {
                    if (recorded) {
                        return;
                    }
                    recorded = true;
                    LunoBootDiagnostics.mark("LUNO_BOOT_08_FIRST_FRAME");
                    diagnosticWebView.post(() -> {
                        ViewTreeObserver currentObserver = diagnosticWebView.getViewTreeObserver();
                        if (currentObserver.isAlive()) {
                            currentObserver.removeOnDrawListener(this);
                        }
                        bootProbeDeadlineMs = SystemClock.uptimeMillis() + BOOT_PROBE_TIMEOUT_MS;
                        bootDiagnosticsHandler.post(bootWebProbe);
                    });
                }
            });
        } catch (Throwable error) {
            LunoBootDiagnostics.failure("LUNO_BOOT_07_WEBVIEW_CREATED state=failed", error);
        }
    }

    private void applySystemUiSafely() {
        try {
            hideSystemBars();
        } catch (Throwable error) {
            Log.w(TAG, "Immersive system UI is unavailable on this device", error);
            LunoBootDiagnostics.failure("LUNO_BOOT_SYSTEM_UI_FAILED", error);
        }
    }

    private void hideSystemBars() {
        Window window = getWindow();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.setNavigationBarContrastEnforced(false);
        }

        // The Web surface covers the display; HTML owns safe-area padding.
        WindowInsetsControllerCompat controller =
                new WindowInsetsControllerCompat(window, window.getDecorView());
        controller.hide(WindowInsetsCompat.Type.systemBars());
        controller.setSystemBarsBehavior(
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
    }
}
