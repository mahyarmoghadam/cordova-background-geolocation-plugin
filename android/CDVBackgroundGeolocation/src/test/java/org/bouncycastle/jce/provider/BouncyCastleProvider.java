package org.bouncycastle.jce.provider;

import java.security.Provider;

/**
 * Test-only stub used to satisfy Robolectric's optional BouncyCastle integration.
 *
 * The real BouncyCastle dependency previously triggered Jetifier / AndroidX
 * transform issues in this standalone build.
 */
public class BouncyCastleProvider extends Provider {
    public BouncyCastleProvider() {
        super("BC", 1.0, "Stub BouncyCastle provider for unit tests");
    }
}
