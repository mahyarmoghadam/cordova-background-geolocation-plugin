package com.marianhello.bgloc.schedule;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** Single exact alarm that wakes {@link ScheduleReceiver} at the next window start or end. */
public final class ScheduleAlarm {
    private static final int REQUEST_CODE = 0x5C4E;

    private ScheduleAlarm() {}

    private static PendingIntent pendingIntent(Context context) {
        Intent intent = new Intent(context, ScheduleReceiver.class);
        intent.setAction(ScheduleReceiver.ACTION_EVALUATE);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT
                | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags);
    }

    /** Schedules the alarm, or cancels it when triggerAtMs is null. */
    public static void scheduleAt(Context context, Long triggerAtMs) {
        if (triggerAtMs == null) {
            cancel(context);
            return;
        }
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (am == null) {
            return;
        }
        PendingIntent pi = pendingIntent(context);
        boolean canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms();
        if (canExact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi);
            } catch (SecurityException e) {
                // Exact-alarm access revoked between the check and the call.
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi);
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // Exact alarms revoked by the user: may fire a few minutes late.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi);
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pi);
        }
    }

    public static void cancel(Context context) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (am != null) {
            am.cancel(pendingIntent(context));
        }
    }
}
