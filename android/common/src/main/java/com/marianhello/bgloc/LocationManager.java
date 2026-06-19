package com.marianhello.bgloc;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.Context;
import android.location.Criteria;
import android.location.Location;
import android.location.LocationListener;
import android.os.Bundle;
import android.os.Looper;

import com.github.jparkie.promise.Promise;
import com.github.jparkie.promise.Promises;
import com.intentfilter.androidpermissions.PermissionManager;
import com.intentfilter.androidpermissions.models.DeniedPermissions;

import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;

public class LocationManager {
    private Context mContext;
    private static LocationManager mLocationManager;
    private static final ExecutorService sCurrentLocationExecutor = Executors.newCachedThreadPool(new ThreadFactory() {
        private final AtomicInteger mThreadNumber = new AtomicInteger(1);

        @Override
        public Thread newThread(Runnable r) {
            Thread thread = new Thread(r, "LocationManager.CurrentLocation-" + mThreadNumber.getAndIncrement());
            thread.setDaemon(true);
            return thread;
        }
    });

    public static final String[] PERMISSIONS = {
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_FINE_LOCATION
    };

    private LocationManager(Context context) {
        mContext = context;
    }

    public class PermissionDeniedException extends Exception {}

    public static LocationManager getInstance(Context context) {
        if (mLocationManager == null) {
            mLocationManager = new LocationManager(context.getApplicationContext());
        }
        return mLocationManager;
    }

    public Promise<Location> getCurrentLocation(final int timeout, final long maximumAge, final boolean enableHighAccuracy) {
        final Promise<Location> promise = Promises.promise();

        checkPermissions(new PermissionManager.PermissionRequestListener() {
            @Override
            public void onPermissionGranted() {
                executeCurrentLocationLookup(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            Location currentLocation = getCurrentLocationNoCheck(timeout, maximumAge, enableHighAccuracy);
                            promise.set(currentLocation);
                        } catch (TimeoutException e) {
                            promise.setError(e);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                            promise.setError(e);
                        } catch (RuntimeException e) {
                            promise.setError(e);
                        }
                    }
                });
            }

            @Override
            public void onPermissionDenied(DeniedPermissions deniedPermissions) {
                promise.setError(new PermissionDeniedException());
            }
        });

        return promise;
    }

    protected void checkPermissions(PermissionManager.PermissionRequestListener listener) {
        PermissionManager permissionManager = PermissionManager.getInstance(mContext);
        permissionManager.checkPermissions(Arrays.asList(PERMISSIONS), listener);
    }

    protected void executeCurrentLocationLookup(Runnable lookupRunnable) {
        sCurrentLocationExecutor.execute(lookupRunnable);
    }

    /**
     * Get current location without permission checking
     *
     * @param timeout
     * @param maximumAge
     * @param enableHighAccuracy
     * @return
     * @throws InterruptedException
     * @throws TimeoutException
     */
    @SuppressLint("MissingPermission")
    public Location getCurrentLocationNoCheck(int timeout, long maximumAge, boolean enableHighAccuracy) throws InterruptedException, TimeoutException {
        final long minLocationTime = System.currentTimeMillis() - maximumAge;
        final android.location.LocationManager locationManager = (android.location.LocationManager) mContext.getSystemService(Context.LOCATION_SERVICE);

        Location lastKnownGPSLocation = locationManager.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER);
        if (lastKnownGPSLocation != null && lastKnownGPSLocation.getTime() >= minLocationTime) {
            return lastKnownGPSLocation;
        }

        Location lastKnownNetworkLocation = locationManager.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER);
        if (lastKnownNetworkLocation != null && lastKnownNetworkLocation.getTime() >= minLocationTime) {
            return lastKnownNetworkLocation;
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException("Blocking current location lookup cannot run on the main thread");
        }

        Criteria criteria = new Criteria();
        criteria.setAccuracy(enableHighAccuracy ? Criteria.ACCURACY_FINE : Criteria.ACCURACY_COARSE);

        CurrentLocationListener locationListener = new CurrentLocationListener();
        locationManager.requestSingleUpdate(criteria, locationListener, Looper.getMainLooper());

        if (!locationListener.mCountDownLatch.await(timeout, TimeUnit.MILLISECONDS)) {
            locationManager.removeUpdates(locationListener);
            throw new TimeoutException();
        }

        if (locationListener.mLocation != null) {
            return locationListener.mLocation;
        }

        return null;
    }

    static class CurrentLocationListener implements LocationListener {
        Location mLocation = null;
        final CountDownLatch mCountDownLatch = new CountDownLatch(1);

        @Override
        public void onLocationChanged(Location location) {
            mLocation = location;
            mCountDownLatch.countDown();
        }

        @Override
        public void onStatusChanged(String s, int i, Bundle bundle) {

        }

        @Override
        public void onProviderEnabled(String s) {

        }

        @Override
        public void onProviderDisabled(String s) {

        }
    }
}
