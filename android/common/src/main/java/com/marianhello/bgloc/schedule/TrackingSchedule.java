package com.marianhello.bgloc.schedule;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Immutable list of absolute tracking windows [start, end) in epoch ms.
 * A schedule without windows (null list) is unrestricted; an empty list blocks tracking.
 */
public final class TrackingSchedule {
    private final List<long[]> windows;

    private TrackingSchedule(List<long[]> windows) {
        this.windows = windows;
    }

    public static TrackingSchedule unrestricted() {
        return new TrackingSchedule(null);
    }

    public static TrackingSchedule fromJson(String json) throws JSONException {
        JSONArray array = new JSONArray(json);
        List<long[]> list = new ArrayList<>(array.length());
        for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.getJSONObject(i);
            long start = item.getLong("start");
            long end = item.getLong("end");
            if (end <= start) {
                throw new JSONException("Tracking window end must be after start");
            }
            list.add(new long[]{start, end});
        }
        Collections.sort(list, new Comparator<long[]>() {
            @Override
            public int compare(long[] a, long[] b) {
                return a[0] < b[0] ? -1 : (a[0] == b[0] ? 0 : 1);
            }
        });
        return new TrackingSchedule(Collections.unmodifiableList(list));
    }

    public String toJson() throws JSONException {
        JSONArray array = new JSONArray();
        if (windows != null) {
            for (long[] w : windows) {
                array.put(new JSONObject().put("start", w[0]).put("end", w[1]));
            }
        }
        return array.toString();
    }

    public boolean isRestricted() {
        return windows != null;
    }

    public boolean isAllowed(long nowMs) {
        return !isRestricted() || currentWindowEnd(nowMs) != null;
    }

    /** End of the window containing now, or null. */
    public Long currentWindowEnd(long nowMs) {
        if (windows == null) {
            return null;
        }
        for (long[] w : windows) {
            if (nowMs >= w[0] && nowMs < w[1]) {
                return w[1];
            }
        }
        return null;
    }

    /** First window start strictly after now, or null. */
    public Long nextWindowStart(long nowMs) {
        if (windows == null) {
            return null;
        }
        for (long[] w : windows) {
            if (w[0] > nowMs) {
                return w[0];
            }
        }
        return null;
    }
}
