/**
 * Validates a store key against the current user. The membership and effective-Account
 * check depends on the G1/G2 mapping work, so it is isolated here behind one method.
 * TODO(G1/G2): replace the body with the approved membership + effective Account check.
 */
public with sharing class NotificationStoreAccess {
    private static final Pattern KEY = Pattern.compile('^[A-Za-z0-9_\\-]{1,80}$');

    public static String validate(String storeKey) {
        if (String.isBlank(storeKey)) {
            return null; // rows without a store scope only
        }
        if (!KEY.matcher(storeKey).matches()) {
            throw new AuraHandledException(Label.Nimbus_Notif_Invalid_Store);
        }
        return storeKey;
    }
}
