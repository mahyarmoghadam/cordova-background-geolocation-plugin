package android.view;

/**
 * Test-only stub for Robolectric running with older android-all stubs (e.g. SDK 28).
 */
public class SurfaceControl {
    public SurfaceControl() {
        // no-op
    }

    public void release() {
        // no-op
    }

    public boolean isValid() {
        return true;
    }

    public static class Transaction {
        public Transaction() {
            // no-op
        }

        public void apply() {
            // no-op
        }
    }

    public static class Builder {
        public Builder() {
            // no-op
        }

        public SurfaceControl build() {
            return new SurfaceControl();
        }
    }
}
