package com.marianhello.bgloc.schedule;

import android.content.Context;
import android.content.Intent;
import android.os.Build;

import com.marianhello.bgloc.BackgroundGeolocationFacade;
import com.marianhello.bgloc.service.CommandId;
import com.marianhello.bgloc.service.LocationServiceImpl;
import com.marianhello.bgloc.service.LocationServiceIntentBuilder;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** Applies the stored schedule from outside the service (alarm, boot, new windows). */
public final class ScheduleEvaluator {
    private static final Logger logger = LoggerFactory.getLogger(ScheduleEvaluator.class);

    private ScheduleEvaluator() {}

    public static void evaluate(Context context) {
        if (!TrackingScheduleStore.isArmed(context)) {
            ScheduleAlarm.cancel(context);
            return;
        }
        TrackingSchedule schedule = TrackingScheduleStore.load(context);
        long now = System.currentTimeMillis();
        try {
            if (LocationServiceImpl.isRunning()) {
                // Running in foreground: the service decides (stay active or enter standby).
                Intent intent = new LocationServiceIntentBuilder(context)
                        .setCommand(CommandId.EVALUATE_SCHEDULE)
                        .build();
                context.startService(intent);
            } else if (schedule.isAllowed(now)) {
                if (!BackgroundGeolocationFacade.hasPermissions(context, BackgroundGeolocationFacade.PERMISSIONS)) {
                    // The service would abort without calling startForeground() (FGS timeout crash).
                    logger.warn("Tracking window open but location permission missing; not starting");
                    return;
                }
                Intent intent = new LocationServiceIntentBuilder(context)
                        .setCommand(CommandId.START_FOREGROUND_SERVICE)
                        .build();
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent);
                } else {
                    context.startService(intent);
                }
            } else {
                ScheduleAlarm.scheduleAt(context, schedule.nextWindowStart(now));
            }
        } catch (RuntimeException e) {
            // e.g. ForegroundServiceStartNotAllowedException when the alarm was not exact.
            logger.error("Schedule evaluation failed", e);
        }
    }
}
