package com.marianhello.backgroundgeolocation;

import android.content.ComponentName;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;

import com.marianhello.bgloc.service.LocationServiceIntentBuilder;
import com.marianhello.bgloc.service.LocationServiceProxy;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.hamcrest.core.IsEqual.equalTo;
import static org.junit.Assert.assertThat;
import static org.junit.Assert.assertTrue;

@RunWith(RobolectricTestRunner.class)
@org.robolectric.annotation.Config(sdk = 30, manifest = org.robolectric.annotation.Config.NONE)
public class LocationServiceProxyThreadingTest {

    @Test
    public void stopCommandsRunOffMainThreadAndPreserveOrder() throws Exception {
        RecordingContext context = new RecordingContext(RuntimeEnvironment.getApplication(), 2);
        TestLocationServiceProxy proxy = new TestLocationServiceProxy(context);

        proxy.stopHeadlessTask();
        proxy.stopForeground();

        assertTrue(context.awaitCommands());
        assertThat(context.commandIds, equalTo(Arrays.asList(8, 3)));
        assertThat(context.threadNames.size(), equalTo(2));
        for (String threadName : context.threadNames) {
            assertTrue(threadName.startsWith("LocationServiceProxy.Commands"));
        }
    }

    private static class TestLocationServiceProxy extends LocationServiceProxy {
        private TestLocationServiceProxy(Context context) {
            super(context);
        }

        @Override
        public boolean isStarted() {
            return true;
        }
    }

    private static class RecordingContext extends ContextWrapper {
        private final CountDownLatch latch;
        private final List<Integer> commandIds = Collections.synchronizedList(new ArrayList<Integer>());
        private final List<String> threadNames = Collections.synchronizedList(new ArrayList<String>());

        private RecordingContext(Context base, int expectedCommands) {
            super(base);
            latch = new CountDownLatch(expectedCommands);
        }

        @Override
        public Context getApplicationContext() {
            return this;
        }

        @Override
        public ComponentName startService(Intent service) {
            record(service);
            return service.getComponent();
        }

        @Override
        public ComponentName startForegroundService(Intent service) {
            record(service);
            return service.getComponent();
        }

        private void record(Intent service) {
            commandIds.add(LocationServiceIntentBuilder.getCommand(service).getId());
            threadNames.add(Thread.currentThread().getName());
            latch.countDown();
        }

        private boolean awaitCommands() throws InterruptedException {
            return latch.await(5, TimeUnit.SECONDS);
        }
    }
}
