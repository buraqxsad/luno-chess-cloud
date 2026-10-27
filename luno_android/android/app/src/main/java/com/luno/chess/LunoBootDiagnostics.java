package com.luno.chess;

import android.util.Log;

final class LunoBootDiagnostics {
    private static final String TAG = "LunoBoot";

    private LunoBootDiagnostics() {}

    static void mark(String marker) {
        if (BuildConfig.LUNO_BOOT_DIAGNOSTICS) {
            Log.i(TAG, marker);
        }
    }

    static void failure(String marker, Throwable error) {
        if (BuildConfig.LUNO_BOOT_DIAGNOSTICS) {
            Log.e(TAG, marker + " type=" + error.getClass().getName());
        }
    }
}
