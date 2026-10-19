/**
 * Test-only escape hatch for the integrity triggers. The flag is private, so production code
 * cannot set it; only test classes (via @TestVisible) can, to seed already-Active fixtures.
 */
public without sharing class NotificationGuard {
    @TestVisible
    private static Boolean bypass = false;

    public static Boolean isBypassed() {
        return bypass;
    }
}
