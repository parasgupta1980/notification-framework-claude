/**
 * Deterministic identity keys (design section 5). Every key is a SHA-256 digest rendered as
 * 64 hex characters, which fits the Text(64) unique External Id fields. Each part is length-prefixed
 * before hashing so that ('a|b','c') and ('a','b|c') can never collide.
 */
public with sharing class NotificationKeys {
    public static String hash(List<String> parts) {
        List<String> encoded = new List<String>();
        for (String p : parts) {
            String v = p == null ? '' : p;
            encoded.add(v.length() + ':' + v);
        }
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(String.join(encoded, '|')));
        return EncodingUtil.convertToHex(digest);
    }

    /** EventKey = hash(sourceApplication | businessEventId) */
    public static String eventKey(String sourceApplication, String businessEventId) {
        return hash(new List<String>{ sourceApplication, businessEventId });
    }

    /** DeliveryKey = hash(EventKey | definitionKey | recipientUserId | channel | scopeKey) */
    public static String deliveryKey(
        String eventKey, String definitionKey, String recipientId, String channel, String scopeKey
    ) {
        return hash(new List<String>{ eventKey, definitionKey, recipientId, channel, scopeKey });
    }

    /** Unique per Definition and Locale. */
    public static String definitionLocaleKey(Id definitionId, String locale) {
        return hash(new List<String>{ definitionId == null ? null : String.valueOf(definitionId), locale });
    }

    /** Hash of the minimized context, used to detect a conflicting payload on the same event key (409). */
    public static String payloadHash(String contextJson) {
        return hash(new List<String>{ contextJson });
    }
}
