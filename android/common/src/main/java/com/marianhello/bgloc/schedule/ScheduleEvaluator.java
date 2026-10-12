package com.marianhello.bgloc.schedule;

import android.content.Context;
import android.content.Intent;
import android.os.Build;

import com.marianhello.bgloc.BackgroundGeolocationFacade;
import com.marianhello.bgloc.data.DAOFactory;
import com.marianhello.bgloc.service.CommandId;
import com.marianhello.bgloc.service.LocationServiceImpl;
import com.marianhello.bgloc.service.LocationServiceIntentBuilder;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** Applies the stored schedule from outside the service (alarm, boot, new windows). */
public final class ScheduleEvaluator {
    private static final Logger logger = LoggerFactory.getLogger(ScheduleEvaluator.class);

    /** Command argument marking a START_FOREGROUND_SERVICE as schedule-triggered. */
    public static final String START_ORIGIN_SCHEDULE = "schedule";

    private static final String[] BACKGROUND_PERMISSIONS = {
            "android.permission.ACCESS_BACKGROUND_LOCATION"
    };

    private ScheduleEvaluator() {}

    public static void evaluate(Context context) {
        TrackingSchedule schedule = TrackingScheduleStore.load(context);
        long now = System.currentTimeMillis();
        boolean allowed = schedule.isAllowed(now);

        if (!allowed && !LocationServiceImpl.isRunning()) {
            // Process may have died inside a window: never let stored fixes upload later
            // (SyncAdapter) from outside a window. A running service purges in enterStandby().
            purgeStoredLocations(context);
        }

        if (!TrackingScheduleStore.isArmed(context)) {
            ScheduleAlarm.cancel(context);
            return;
        }
        try {
            if (LocationServiceImpl.isRunning()) {
                // Running in foreground: the service decides (stay active or enter standby).
                Intent intent = new LocationServiceIntentBuilder(context)
                        .setCommand(CommandId.EVALUATE_SCHEDULE)
                        .build();
                context.startService(intent);
            } else if (allowed) {
                if (!hasStartPermissions(context)) {
                    // Starting would fail (SecurityException / FGS timeout). Stay armed and
                    // retry at the next window start.
                    logger.warn("Tracking window open but location permission missing; retry at next window");
                    ScheduleAlarm.scheduleAt(context, schedule.nextWindowStart(now));
                    return;
                }
                Intent intent = new LocationServiceIntentBuilder(context)
                        .setCommand(CommandId.START_FOREGROUND_SERVICE, START_ORIGIN_SCHEDULE)
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
            // Stay armed: wake up again at the next window start.
            logger.error("Schedule evaluation failed; retry at next window", e);
            try {
                ScheduleAlarm.scheduleAt(context, schedule.nextWindowStart(now));
            } catch (RuntimeException ignored) {
                // nothing more we can do
            }
        }
    }

    private static boolean hasStartPermissions(Context context) {
        if (!BackgroundGeolocationFacade.hasPermissions(context, BackgroundGeolocationFacade.PERMISSIONS)) {
            return false;
        }
        // Started from the background (alarm / boot): a location FGS needs background location on Q+.
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
                || BackgroundGeolocationFacade.hasPermissions(context, BACKGROUND_PERMISSIONS);
    }

    private static void purgeStoredLocations(Context context) {
        try {
            DAOFactory.createLocationDAO(context).deleteAllLocations();
        } catch (RuntimeException e) {
            logger.error("Purging stored locations failed", e);
        }
    }
}
