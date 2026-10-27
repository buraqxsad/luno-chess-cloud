package com.luno.chess;

import android.content.Context;
import android.text.TextUtils;

import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.appcheck.AppCheckProviderFactory;
import com.google.firebase.appcheck.FirebaseAppCheck;

import java.lang.reflect.Method;
import java.util.Locale;

final class LunoAppCheckInitializer {
    private static boolean initialized;

    private LunoAppCheckInitializer() {}

    static synchronized boolean initialize(Context context) {
        if (initialized) {
            LunoBootDiagnostics.mark("LUNO_BOOT_09_FIREBASE_INIT state=already_ready");
            LunoBootDiagnostics.mark("LUNO_BOOT_10_APPCHECK_INIT state=already_ready");
            return true;
        }
        LunoBootDiagnostics.mark("LUNO_BOOT_09_FIREBASE_INIT_BEGIN");
        FirebaseOptions options = firebaseOptions(context);
        if (options == null) {
            LunoBootDiagnostics.mark("LUNO_BOOT_09_FIREBASE_INIT state=skipped_no_config");
            LunoBootDiagnostics.mark("LUNO_BOOT_10_APPCHECK_INIT state=skipped_no_firebase");
            return false;
        }

        Context appContext = context.getApplicationContext();
        FirebaseApp app;
        try {
            app = FirebaseApp.getApps(appContext).isEmpty()
                ? FirebaseApp.initializeApp(appContext, options)
                : FirebaseApp.getInstance();
            LunoBootDiagnostics.mark("LUNO_BOOT_09_FIREBASE_INIT state=ready");
        } catch (RuntimeException | Error error) {
            LunoBootDiagnostics.failure("LUNO_BOOT_09_FIREBASE_INIT state=failed", error);
            throw error;
        }

        String factoryClass = BuildConfig.LUNO_APPCHECK_PROVIDER_FACTORY;
        LunoBootDiagnostics.mark("LUNO_BOOT_10_APPCHECK_INIT_BEGIN");
        try {
            seedQaDebugSecret(appContext, app);
            Class<?> type = Class.forName(factoryClass);
            Method getInstance = type.getMethod("getInstance");
            Object value = getInstance.invoke(null);
            if (!(value instanceof AppCheckProviderFactory)) {
                throw new IllegalStateException("Invalid App Check provider factory");
            }
            FirebaseAppCheck.getInstance(app).installAppCheckProviderFactory(
                (AppCheckProviderFactory) value
            );
            initialized = true;
            LunoBootDiagnostics.mark("LUNO_BOOT_10_APPCHECK_INIT state=ready");
            return true;
        } catch (ReflectiveOperationException error) {
            LunoBootDiagnostics.failure("LUNO_BOOT_10_APPCHECK_INIT state=failed", error);
            throw new IllegalStateException("App Check provider is unavailable", error);
        } catch (RuntimeException | Error error) {
            LunoBootDiagnostics.failure("LUNO_BOOT_10_APPCHECK_INIT state=failed", error);
            throw error;
        }
    }

    private static void seedQaDebugSecret(Context context, FirebaseApp app) {
        String secret = BuildConfig.LUNO_APPCHECK_DEBUG_SECRET;
        if (TextUtils.isEmpty(secret)) {
            return;
        }
        String store = String.format(
            Locale.ROOT,
            "com.google.firebase.appcheck.debug.store.%s",
            app.getPersistenceKey()
        );
        context.getSharedPreferences(store, Context.MODE_PRIVATE)
            .edit()
            .putString("com.google.firebase.appcheck.debug.DEBUG_SECRET", secret)
            .apply();
    }

    private static FirebaseOptions firebaseOptions(Context context) {
        try {
            FirebaseOptions options = FirebaseOptions.fromResource(context);
            return options == null || TextUtils.isEmpty(options.getApplicationId()) ? null : options;
        } catch (RuntimeException error) {
            return null;
        }
    }
}
