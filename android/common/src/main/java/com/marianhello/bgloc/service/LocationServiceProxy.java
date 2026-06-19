package com.marianhello.bgloc.service;

import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Process;

import com.marianhello.bgloc.Config;
import com.marianhello.logging.LoggerManager;

public class LocationServiceProxy implements LocationService, LocationServiceInfo {
    private static final Object sCommandHandlerLock = new Object();
    private static Handler sCommandHandler;

    private final Context mContext;
    private final LocationServiceIntentBuilder mIntentBuilder;
    private final org.slf4j.Logger logger;

    public LocationServiceProxy(Context context) {
        Context applicationContext = context.getApplicationContext();
        mContext = applicationContext != null ? applicationContext : context;
        mIntentBuilder = new LocationServiceIntentBuilder(mContext);
        logger = LoggerManager.getLogger(LocationServiceProxy.class);
    }

    @Override
    public void configure(Config config) {
        // do not start service if it was not already started
        // FIXES:
        // https://github.com/mauron85/react-native-background-geolocation/issues/360
        // https://github.com/mauron85/cordova-plugin-background-geolocation/issues/551
        // https://github.com/mauron85/cordova-plugin-background-geolocation/issues/552
        Intent intent = mIntentBuilder
                .setCommand(CommandId.CONFIGURE, config)
                .build();
        executeIntentCommand(intent, true);
    }

    @Override
    public void registerHeadlessTask(String taskRunnerClass) {
        Intent intent = mIntentBuilder
                .setCommand(CommandId.REGISTER_HEADLESS_TASK, taskRunnerClass)
                .build();
        executeIntentCommand(intent);
    }

    @Override
    public void startHeadlessTask() {
        Intent intent = mIntentBuilder
                .setCommand(CommandId.START_HEADLESS_TASK)
                .build();
        executeIntentCommand(intent, true);
    }

    @Override
    public void stopHeadlessTask() {
        Intent intent = mIntentBuilder
                .setCommand(CommandId.STOP_HEADLESS_TASK)
                .build();
        executeIntentCommand(intent, true);
    }

    @Override
    public void executeProviderCommand(int command, int arg) {
        // TODO
    }

    @Override
    public void start() {
        Intent intent = mIntentBuilder.setCommand(CommandId.START).build();
//        intent.addFlags(Intent.FLAG_FROM_BACKGROUND);
        // start service to keep service running even if no clients are bound to it
        executeIntentCommand(intent);
    }

    @Override
    public void startForegroundService() {
        final Intent intent = mIntentBuilder.setCommand(CommandId.START_FOREGROUND_SERVICE).build();
        postServiceCommand(new Runnable() {
            @Override
            public void run() {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        mContext.startForegroundService(intent);
                    } else {
                        mContext.startService(intent);
                    }
                } catch (RuntimeException e) {
                    logger.error("Failed to start foreground service", e);
                }
            }
        });
    }

    @Override
    public void stop() {
        Intent intent = mIntentBuilder.setCommand(CommandId.STOP).build();
        executeIntentCommand(intent, true);
    }

    @Override
    public void stopForeground() {
        Intent intent = mIntentBuilder.setCommand(CommandId.STOP_FOREGROUND).build();
        executeIntentCommand(intent, true);
    }

    @Override
    public void startForeground() {
        Intent intent = mIntentBuilder.setCommand(CommandId.START_FOREGROUND).build();
        executeIntentCommand(intent, true);
    }

    @Override
    public boolean isStarted() {
        LocationServiceInfo serviceInfo = new LocationServiceInfoImpl(mContext);
        return serviceInfo.isStarted();
    }

    public boolean isRunning() {
        if (isStarted()) {
            return LocationServiceImpl.isRunning();
        }
        return false;
    }

    @Override
    public boolean isBound() {
        LocationServiceInfo serviceInfo = new LocationServiceInfoImpl(mContext);
        return serviceInfo.isBound();
    }

    private void executeIntentCommand(final Intent intent) {
        executeIntentCommand(intent, false);
    }

    private void executeIntentCommand(final Intent intent, final boolean requireStarted) {
        postServiceCommand(new Runnable() {
            @Override
            public void run() {
                if (requireStarted && !isStarted()) { return; }

                try {
                    mContext.startService(intent);
                } catch (RuntimeException e) {
                    logger.error("Failed to start service command", e);
                }
            }
        });
    }

    private static void postServiceCommand(Runnable command) {
        getCommandHandler().post(command);
    }

    private static Handler getCommandHandler() {
        synchronized (sCommandHandlerLock) {
            if (sCommandHandler == null) {
                HandlerThread commandThread = new HandlerThread(
                        "LocationServiceProxy.Commands",
                        Process.THREAD_PRIORITY_BACKGROUND);
                commandThread.start();
                sCommandHandler = new Handler(commandThread.getLooper());
            }
            return sCommandHandler;
        }
    }
}
