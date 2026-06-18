package com.marianhello.backgroundgeolocation;

import com.marianhello.bgloc.service.LocationServiceImpl;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mockito;
import org.robolectric.RobolectricTestRunner;

import java.lang.reflect.Field;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

@RunWith(RobolectricTestRunner.class)
@org.robolectric.annotation.Config(sdk = 30, manifest = org.robolectric.annotation.Config.NONE)
public class LocationServiceImplTest {

    @Test
    public void handleStartForegroundRuntimeExceptionStopsServiceWhenForegroundStartNotAllowed() throws Exception {
        TestLocationServiceImpl service = new TestLocationServiceImpl(true);
        setField(service, "logger", Mockito.mock(org.slf4j.Logger.class));
        setField(service, "mIsInForeground", true);

        service.invokeHandleStartForegroundRuntimeException(new RuntimeException("denied"));

        assertTrue(service.stopCalled);
        assertFalse((Boolean) getField(service, "mIsInForeground"));
    }

    @Test
    public void handleStartForegroundRuntimeExceptionRethrowsUnexpectedRuntimeExceptions() throws Exception {
        TestLocationServiceImpl service = new TestLocationServiceImpl(false);
        setField(service, "logger", Mockito.mock(org.slf4j.Logger.class));
        RuntimeException failure = new RuntimeException("boom");

        try {
            service.invokeHandleStartForegroundRuntimeException(failure);
            fail("Expected runtime exception to be rethrown");
        } catch (RuntimeException e) {
            assertSame(failure, e);
        }

        assertFalse(service.stopCalled);
    }

    private static Object getField(Object target, String fieldName) throws Exception {
        Field field = LocationServiceImpl.class.getDeclaredField(fieldName);
        field.setAccessible(true);
        return field.get(target);
    }

    private static void setField(Object target, String fieldName, Object value) throws Exception {
        Field field = LocationServiceImpl.class.getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }

    private static class TestLocationServiceImpl extends LocationServiceImpl {
        private final boolean startNotAllowed;
        private boolean stopCalled;

        private TestLocationServiceImpl(boolean startNotAllowed) {
            this.startNotAllowed = startNotAllowed;
        }

        @Override
        public synchronized void stop() {
            stopCalled = true;
        }

        @Override
        protected boolean isForegroundServiceStartNotAllowedException(RuntimeException e) {
            return startNotAllowed;
        }

        private void invokeHandleStartForegroundRuntimeException(RuntimeException e) {
            handleStartForegroundRuntimeException(e);
        }
    }
}