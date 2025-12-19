package org.bouncycastle.jce.provider;

import java.security.Provider;

public final class BouncyCastleProvider extends Provider {
    private static final long serialVersionUID = 1L;

    public BouncyCastleProvider() {
        super("BC", 1.0, "Test-only stub BouncyCastle provider");
    }
}
