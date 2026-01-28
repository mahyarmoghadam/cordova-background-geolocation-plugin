package com.marianhello.bgloc.reminder;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.app.NotificationManager;

import com.marianhello.bgloc.Config;
import com.marianhello.bgloc.data.ConfigurationDAO;
import com.marianhello.bgloc.data.DAOFactory;
import com.marianhello.bgloc.service.LocationServiceImpl;
import com.marianhello.logging.LoggerManager;

public class ReminderReceiver extends BroadcastReceiver {

    private static final org.slf4j.Logger logger = LoggerManager.getLogger(ReminderReceiver.class);

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) return;

        ConfigurationDAO dao = DAOFactory.createConfigurationDAO(context);
        Config config;
        try {
            config = dao.retrieveConfiguration();
        } catch (Exception e) {
            logger.warn("Failed to load config", e);
            return;
        }
        if (config == null) {
            logger.debug("No config available; skipping reminder action {}", action);
            return;
        }

        switch (action) {
            case ReminderHelper.ACTION_SHOW_REMINDER:
                handleShowReminder(context, config);
                break;
            case ReminderHelper.ACTION_TAP:
                handleReminderTap(context);
                break;
            case ReminderHelper.ACTION_STOP:
                ReminderHelper.cancel(context);
                ReminderHelper.sendStopCommand(context);
                break;
            case ReminderHelper.ACTION_SNOOZE:
                int snoozeMinutes = intent.getIntExtra("extra_snooze_minutes", ReminderHelper.resolveSnoozeMinutes(config));
                ReminderHelper.cancel(context);
                ReminderHelper.scheduleSnooze(context, config, snoozeMinutes);
                break;
            case ReminderHelper.ACTION_MUTE:
                ReminderHelper.cancel(context);
                break;
            default:
                break;
        }
    }

    private void handleReminderTap(Context context) {
        long timestamp = System.currentTimeMillis();
        ReminderHelper.recordReminderNotificationTap(context);
        ReminderHelper.sendReminderNotificationTapBroadcast(context, timestamp);
        ReminderHelper.cancel(context);

        Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            context.startActivity(launchIntent);
        }
    }

    private void handleShowReminder(Context context, Config config) {
        if (!LocationServiceImpl.isRunning()) {
            logger.debug("Service not running, skipping reminder");
            ReminderHelper.cancel(context);
            return;
        }
        if (!ReminderHelper.areNotificationsEnabled(context)) {
            ReminderHelper.cancel(context);
            logger.debug("Notifications disabled, skipping reminder");
            return;
        }
        int snoozeMinutes = ReminderHelper.resolveSnoozeMinutes(config);
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.notify(ReminderHelper.REMINDER_NOTIFICATION_ID, ReminderHelper.buildReminderNotification(context, config, snoozeMinutes));
        }
        ReminderHelper.clearScheduledTriggerAt(context);
    }
}
