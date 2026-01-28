package com.marianhello.bgloc.reminder;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;

import com.marianhello.bgloc.Config;
import com.marianhello.bgloc.data.ConfigurationDAO;
import com.marianhello.bgloc.data.DAOFactory;
import com.marianhello.bgloc.service.LocationServiceIntentBuilder;
import com.marianhello.bgloc.service.LocationServiceImpl;
import com.marianhello.bgloc.service.LocationServiceProxy;
import com.marianhello.bgloc.sync.NotificationHelper;
import com.marianhello.logging.LoggerManager;

/**
 * Schedules and shows tracking reminder notifications.
 */
public final class ReminderHelper {
    public static final String ACTION_SHOW_REMINDER = "com.marianhello.bgloc.ACTION_SHOW_REMINDER";
    public static final String ACTION_STOP = "com.marianhello.bgloc.ACTION_REMINDER_STOP";
    public static final String ACTION_SNOOZE = "com.marianhello.bgloc.ACTION_REMINDER_SNOOZE";
    public static final String ACTION_MUTE = "com.marianhello.bgloc.ACTION_REMINDER_MUTE";
    public static final String ACTION_TAP = "com.marianhello.bgloc.ACTION_REMINDER_TAP";
    public static final String ACTION_REMINDER_TAP_INTERNAL = "com.marianhello.bgloc.ACTION_REMINDER_TAP_INTERNAL";
    public static final int REMINDER_NOTIFICATION_ID = 2001;

    private static final String EXTRA_SNOOZE_MINUTES = "extra_snooze_minutes";
    public static final String EXTRA_REMINDER_TAP_TIMESTAMP = "extra_reminder_tap_timestamp";
    public static final String EXTRA_REMINDER_NOTIFICATION_TAP = "extra_reminder_notification_tap";

    private static final String PREFS_NAME = "com.marianhello.bgloc.reminder";
    private static final String PREF_KEY_REMINDER_TAP_TIMESTAMP = "reminder_tap_timestamp";
    private static final String PREF_KEY_REMINDER_TRIGGER_AT = "reminder_trigger_at";

    private static final org.slf4j.Logger logger = LoggerManager.getLogger(ReminderHelper.class);

    private ReminderHelper() {}

    public static void schedule(Context context, Config config) {
        if (config == null) return;
        Integer minutes = config.getStillTrackingReminderIntervalMinutes();
        if (minutes == null || minutes <= 0) {
            cancel(context);
            return;
        }
        if (!hasNotificationPermission(context)) {
            logger.info("Notification permission not granted; skipping reminder schedule");
            cancel(context);
            return;
        }

        long triggerAt = System.currentTimeMillis() + minutes * 60_000L;
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pi = pendingIntent(context, ACTION_SHOW_REMINDER, 0, PendingIntent.FLAG_CANCEL_CURRENT);
        if (am != null) {
            scheduleAlarm(am, config, triggerAt, pi);
            setScheduledTriggerAt(context, triggerAt);
        }
        logger.info("Reminder scheduled in {} minutes", minutes);
    }

    public static void scheduleSnooze(Context context, Config config, int snoozeMinutes) {
        if (snoozeMinutes <= 0) return;
        if (!hasNotificationPermission(context)) {
            logger.info("Notification permission not granted; skipping snooze schedule");
            cancel(context);
            return;
        }

        long triggerAt = System.currentTimeMillis() + snoozeMinutes * 60_000L;
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pi = pendingIntent(context, ACTION_SHOW_REMINDER, 0, PendingIntent.FLAG_CANCEL_CURRENT);
        if (am != null) {
            scheduleAlarm(am, config, triggerAt, pi);
            setScheduledTriggerAt(context, triggerAt);
        }
        logger.info("Reminder snoozed for {} minutes", snoozeMinutes);
    }

    /** Snooze reminder if tracking is active and no reminder is already scheduled. */
    public static void snoozeIfEligible(Context context, Config config, Integer overrideMinutes) {
        if (context == null || config == null) {
            return;
        }
        if (!isTrackingActive()) {
            logger.info("Tracking not active; skipping reminder snooze");
            return;
        }
        if (isReminderScheduled(context)) {
            logger.info("Reminder already scheduled; skipping snooze");
            return;
        }
        int minutes = (overrideMinutes != null && overrideMinutes > 0)
                ? overrideMinutes
                : resolveSnoozeMinutes(config);
        if (minutes <= 0) {
            logger.info("No valid snooze interval; skipping snooze");
            return;
        }
        scheduleSnooze(context, config, minutes);
    }

    public static void cancel(Context context) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pi = pendingIntent(context, ACTION_SHOW_REMINDER, 0, PendingIntent.FLAG_NO_CREATE);
        if (am != null && pi != null) {
            am.cancel(pi);
        }
        clearScheduledTriggerAt(context);
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.cancel(REMINDER_NOTIFICATION_ID);
        }
    }

    private static PendingIntent pendingIntent(Context context, String action, int requestCode, int flags) {
        int baseFlags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0;
        Intent intent = new Intent(context, ReminderReceiver.class).setAction(action);
        return PendingIntent.getBroadcast(context, requestCode, intent, baseFlags | flags);
    }

    static boolean isReminderScheduled(Context context) {
        Long triggerAt = getScheduledTriggerAt(context);
        if (triggerAt == null) {
            return false;
        }
        long now = System.currentTimeMillis();
        if (triggerAt > now) {
            return true;
        }
        clearScheduledTriggerAt(context);
        return false;
    }

    static void clearScheduledTriggerAt(Context context) {
        if (context == null) {
            return;
        }
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit().remove(PREF_KEY_REMINDER_TRIGGER_AT).apply();
    }

    private static void setScheduledTriggerAt(Context context, long triggerAt) {
        if (context == null) {
            return;
        }
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit().putLong(PREF_KEY_REMINDER_TRIGGER_AT, triggerAt).apply();
    }

    private static Long getScheduledTriggerAt(Context context) {
        if (context == null) {
            return null;
        }
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        long triggerAt = prefs.getLong(PREF_KEY_REMINDER_TRIGGER_AT, 0L);
        return triggerAt == 0L ? null : triggerAt;
    }

    /** Build reminder notification with actions. */
    static Notification buildReminderNotification(Context context, Config config, int snoozeMinutes) {
        NotificationHelper.registerReminderChannel(context);
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, NotificationHelper.REMINDER_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(config.hasStillTrackingReminderTitle() && config.getStillTrackingReminderTitle() != Config.NullString
                        ? config.getStillTrackingReminderTitle()
                : "Tracking is still running")
                .setContentText(config.hasStillTrackingReminderText() && config.getStillTrackingReminderText() != Config.NullString
                        ? config.getStillTrackingReminderText()
                : "Background tracking remains active.")
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT);

        PendingIntent contentIntent = reminderContentIntent(context);
        if (contentIntent != null) {
            builder.setContentIntent(contentIntent);
        }

        String stopLabel = config.hasStillTrackingReminderStopLabel() && config.getStillTrackingReminderStopLabel() != Config.NullString
            ? config.getStillTrackingReminderStopLabel()
            : "Stop";
        String snoozeLabel = config.hasStillTrackingReminderSnoozeLabel() && config.getStillTrackingReminderSnoozeLabel() != Config.NullString
            ? config.getStillTrackingReminderSnoozeLabel()
            : "Snooze";
        String muteLabel = config.hasStillTrackingReminderMuteLabel() && config.getStillTrackingReminderMuteLabel() != Config.NullString
            ? config.getStillTrackingReminderMuteLabel()
            : "Mute";

        // Stop action
        PendingIntent stopPi = pendingIntent(context, ACTION_STOP, 1, PendingIntent.FLAG_CANCEL_CURRENT);
        builder.addAction(0, stopLabel, stopPi);

        // Snooze action
        Intent snoozeIntent = new Intent(context, ReminderReceiver.class).setAction(ACTION_SNOOZE);
        snoozeIntent.putExtra(EXTRA_SNOOZE_MINUTES, snoozeMinutes);
        int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0;
        PendingIntent snoozePi = PendingIntent.getBroadcast(context, 2, snoozeIntent, flags | PendingIntent.FLAG_CANCEL_CURRENT);
        builder.addAction(0, snoozeLabel, snoozePi);

        // Mute action
        PendingIntent mutePi = pendingIntent(context, ACTION_MUTE, 3, PendingIntent.FLAG_CANCEL_CURRENT);
        builder.addAction(0, muteLabel, mutePi);

        return builder.build();
    }

    private static PendingIntent reminderContentIntent(Context context) {
        Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launchIntent == null) {
            return null;
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        launchIntent.putExtra(EXTRA_REMINDER_NOTIFICATION_TAP, true);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getActivity(context, REMINDER_NOTIFICATION_ID, launchIntent, flags);
    }

    public static void recordReminderNotificationTap(Context context) {
        if (context == null) {
            return;
        }
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit().putLong(PREF_KEY_REMINDER_TAP_TIMESTAMP, System.currentTimeMillis()).apply();
    }

    public static Long consumeReminderNotificationTapTimestamp(Context context) {
        if (context == null) {
            return null;
        }
        SharedPreferences prefs = context.getApplicationContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        long timestamp = prefs.getLong(PREF_KEY_REMINDER_TAP_TIMESTAMP, 0L);
        if (timestamp == 0L) {
            return null;
        }
        prefs.edit().remove(PREF_KEY_REMINDER_TAP_TIMESTAMP).apply();
        return timestamp;
    }

    public static void sendReminderNotificationTapBroadcast(Context context, long timestamp) {
        if (context == null) {
            return;
        }
        Intent intent = new Intent(ACTION_REMINDER_TAP_INTERNAL);
        intent.putExtra(EXTRA_REMINDER_TAP_TIMESTAMP, timestamp);
        LocalBroadcastManager.getInstance(context.getApplicationContext()).sendBroadcast(intent);
    }

    private static boolean hasNotificationPermission(Context context) {
        NotificationManagerCompat nm = NotificationManagerCompat.from(context);
        return nm.areNotificationsEnabled();
    }

    public static boolean areNotificationsEnabled(Context context) {
        return hasNotificationPermission(context);
    }

    /** Calculate effective snooze minutes using explicit value or quarter of interval (ceil). */
    static int resolveSnoozeMinutes(Config config) {
        Integer snooze = config.getStillTrackingReminderSnoozeIntervalMinutes();
        if (snooze != null && snooze > 0) {
            return snooze;
        }
        Integer interval = config.getStillTrackingReminderIntervalMinutes();
        if (interval == null || interval <= 0) return 0;
        int derived = (interval + 3) / 4; // ceil(interval/4)
        return Math.max(derived, 1);
    }

    /** Persist config changes (e.g., mute flag) best-effort. */
    static void persistConfig(Context context, Config config) {
        try {
            ConfigurationDAO dao = DAOFactory.createConfigurationDAO(context);
            dao.persistConfiguration(config);
        } catch (Throwable t) {
            logger.warn("Persist config failed", t);
        }
    }

    static void sendStopCommand(Context context) {
        // Use proxy to route stop command through existing service helper
        LocationServiceProxy proxy = new LocationServiceProxy(context.getApplicationContext());
        proxy.stop();
    }

    private static void scheduleAlarm(AlarmManager am, Config config, long triggerAt, PendingIntent pi) {
        boolean exactRequested = config != null && Boolean.TRUE.equals(config.getStillTrackingReminderExactAlarm());
        boolean canUseExact = exactRequested && canScheduleExactAlarm(am);

        if (canUseExact) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            } else {
                am.set(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                am.setWindow(AlarmManager.RTC_WAKEUP, triggerAt, 60_000L, pi); // 1-minute window fallback
            } else {
                am.set(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            }
        }
    }

    private static boolean canScheduleExactAlarm(AlarmManager am) {
        if (Build.VERSION.SDK_INT >= 31) {
            try {
                return (Boolean) AlarmManager.class.getMethod("canScheduleExactAlarms").invoke(am);
            } catch (Throwable t) {
                return false;
            }
        }
        return true;
    }

    static boolean isTrackingActive() {
        return LocationServiceImpl.isRunning();
    }
}
