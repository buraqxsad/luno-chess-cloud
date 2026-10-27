package com.luno.chess;

import android.app.Application;

public final class LunoApplication extends Application {
    static {
        LunoBootDiagnostics.mark("LUNO_BOOT_01_PROCESS");
    }

    @Override
    public void onCreate() {
        super.onCreate();
        LunoBootDiagnostics.mark("LUNO_BOOT_02_APPLICATION");
    }
}
