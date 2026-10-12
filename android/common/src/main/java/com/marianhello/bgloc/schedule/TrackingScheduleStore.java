package com.marianhello.bgloc.schedule;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Persists tracking windows and the "armed" flag (tracking was started and not explicitly stopped)
 * so alarms and boot can resume tracking without the WebView.
 */
public final class TrackingScheduleStore {
    private static final Logger logger = LoggerFactory.getLogger(TrackingScheduleStore.class);
    private static final String PREFS = "bgloc_tracking_schedule";
    private static final String KEY_WINDOWS = "windows";
    private static final String KEY_ARMED = "armed";

    private TrackingScheduleStore() {}

    /**
     * MODE_MULTI_PROCESS: the SyncAdapter runs in the ":sync" process and must see windows written
     * by the main process (re-reads the file when it changed on disk). Deprecated but functional.
     */
    @SuppressWarnings("deprecation")
    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences(PREFS,
                Context.MODE_PRIVATE | Context.MODE_MULTI_PROCESS);
    }

    public static TrackingSchedule load(Context context) {
        String json = prefs(context).getString(KEY_WINDOWS, null);
        if (json == null) {
            return TrackingSchedule.unrestricted();
        }
        try {
            return TrackingSchedule.fromJson(json);
        } catch (JSONException e) {
            // Fail closed: corrupted windows must not allow tracking.
            logger.error("Invalid stored tracking windows", e);
            try {
                return TrackingSchedule.fromJson("[]");
            } catch (JSONException impossible) {
                throw new IllegalStateException(impossible);
            }
        }
    }

    /** Validates and stores the windows JSON array. */
    public static void save(Context context, String json) throws JSONException {
        String normalized = TrackingSchedule.fromJson(json).toJson();
        prefs(context).edit().putString(KEY_WINDOWS, normalized).apply();
    }

    public static boolean isArmed(Context context) {
        return prefs(context).getBoolean(KEY_ARMED, false);
    }

    public static void setArmed(Context context, boolean armed) {
        // commit(): the flag must survive a process kill right after the write.
        prefs(context).edit().putBoolean(KEY_ARMED, armed).commit();
    }
}
