package com.marianhello.bgloc;

import android.content.Context;
import android.location.Location;
import android.os.Looper;

import com.github.jparkie.promise.Promise;
import com.intentfilter.androidpermissions.PermissionManager;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mockito;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;

import java.lang.reflect.Constructor;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

@RunWith(RobolectricTestRunner.class)
@org.robolectric.annotation.Config(sdk = 30, manifest = org.robolectric.annotation.Config.NONE)
public class LocationManagerTest {

    @Test
    public void getCurrentLocationReturnsPromptlyWhenPermissionCallbackRunsLookup() throws Exception {
        final LocationManager manager = Mockito.spy(newLocationManager(RuntimeEnvironment.getApplication()));
        final CountDownLatch lookupStarted = new CountDownLatch(1);
        final CountDownLatch releaseLookup = new CountDownLatch(1);
        final AtomicReference<String> lookupThreadName = new AtomicReference<String>();

        Mockito.doAnswer(new org.mockito.stubbing.Answer<Object>() {
            @Override
            public Object answer(org.mockito.invocation.InvocationOnMock invocation) {
                PermissionManager.PermissionRequestListener listener = (PermissionManager.PermissionRequestListener) invocation.getArgument(0);
                listener.onPermissionGranted();
                return null;
            }
        }).when(manager).checkPermissions(Mockito.any(PermissionManager.PermissionRequestListener.class));

        Mockito.doAnswer(new org.mockito.stubbing.Answer<Location>() {
            @Override
            public Location answer(org.mockito.invocation.InvocationOnMock invocation) throws Throwable {
                lookupThreadName.set(Thread.currentThread().getName());
                lookupStarted.countDown();
                if (!releaseLookup.await(5, TimeUnit.SECONDS)) {
                    throw new TimeoutException("test lookup release timed out");
                }
                return null;
            }
        }).when(manager).getCurrentLocationNoCheck(Mockito.anyInt(), Mockito.anyLong(), Mockito.anyBoolean());

        FutureTask<Promise<Location>> requestTask = new FutureTask<Promise<Location>>(new Callable<Promise<Location>>() {
            @Override
            public Promise<Location> call() {
                return manager.getCurrentLocation(1000, 0, false);
            }
        });
        Thread requestThread = new Thread(requestTask, "LocationManagerTest.Caller");
        requestThread.start();

        Promise<Location> promise = requestTask.get(1, TimeUnit.SECONDS);
        assertTrue(lookupStarted.await(5, TimeUnit.SECONDS));
        assertTrue(lookupThreadName.get().startsWith("LocationManager.CurrentLocation-"));

        releaseLookup.countDown();

        promise.await();
        assertNull(promise.get());
        assertNull(promise.getError());
    }

    @Test
    public void getCurrentLocationNoCheckRejectsBlockingLookupOnMainThread() throws Exception {
        Context context = Mockito.mock(Context.class);
        android.location.LocationManager systemLocationManager = Mockito.mock(android.location.LocationManager.class);
        Mockito.when(context.getSystemService(Context.LOCATION_SERVICE)).thenReturn(systemLocationManager);
        Mockito.when(systemLocationManager.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER)).thenReturn(null);
        Mockito.when(systemLocationManager.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER)).thenReturn(null);

        LocationManager manager = newLocationManager(context);

        assertTrue(Looper.getMainLooper() == Looper.myLooper());

        try {
            manager.getCurrentLocationNoCheck(1000, 0, false);
            fail("Expected getCurrentLocationNoCheck to reject main-thread blocking lookup");
        } catch (IllegalStateException expected) {
            assertTrue(expected.getMessage().contains("main thread"));
        }
    }

    private static LocationManager newLocationManager(Context context) throws Exception {
        Constructor<LocationManager> constructor = LocationManager.class.getDeclaredConstructor(Context.class);
        constructor.setAccessible(true);
        return constructor.newInstance(context);
    }
}