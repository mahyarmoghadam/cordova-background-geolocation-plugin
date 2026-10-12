package com.marianhello.bgloc.schedule;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Wakes up at a window start/end and re-applies the schedule. */
public class ScheduleReceiver extends BroadcastReceiver {
    public static final String ACTION_EVALUATE = "com.marianhello.bgloc.schedule.EVALUATE";

    @Override
    public void onReceive(Context context, Intent intent) {
        ScheduleEvaluator.evaluate(context, false);
    }
}
