package com.marianhello.bgloc.schedule;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

public class TrackingScheduleTest {
    private static final String JSON = "[{\"start\":1000,\"end\":2000},{\"start\":5000,\"end\":6000}]";

    @Test
    public void unrestrictedAlwaysAllows() {
        TrackingSchedule s = TrackingSchedule.unrestricted();
        assertFalse(s.isRestricted());
        assertTrue(s.isAllowed(0));
        assertNull(s.nextWindowStart(0));
    }

    @Test
    public void startInclusiveEndExclusive() throws Exception {
        TrackingSchedule s = TrackingSchedule.fromJson(JSON);
        assertFalse(s.isAllowed(999));
        assertTrue(s.isAllowed(1000));
        assertTrue(s.isAllowed(1999));
        assertFalse(s.isAllowed(2000));
    }

    @Test
    public void nextStartAndCurrentEnd() throws Exception {
        TrackingSchedule s = TrackingSchedule.fromJson(JSON);
        assertEquals(Long.valueOf(2000), s.currentWindowEnd(1500));
        assertNull(s.currentWindowEnd(3000));
        assertEquals(Long.valueOf(5000), s.nextWindowStart(3000));
        assertEquals(Long.valueOf(5000), s.nextWindowStart(1500));
        assertNull(s.nextWindowStart(6000));
    }

    @Test
    public void emptyListBlocksEverything() throws Exception {
        TrackingSchedule s = TrackingSchedule.fromJson("[]");
        assertTrue(s.isRestricted());
        assertFalse(s.isAllowed(1000));
    }

    @Test
    public void roundTripsJson() throws Exception {
        TrackingSchedule s = TrackingSchedule.fromJson(JSON);
        assertTrue(TrackingSchedule.fromJson(s.toJson()).isAllowed(5500));
    }

    @Test(expected = org.json.JSONException.class)
    public void rejectsInvertedWindow() throws Exception {
        TrackingSchedule.fromJson("[{\"start\":2000,\"end\":1000}]");
    }
}
