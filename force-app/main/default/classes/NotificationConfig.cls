/**
 * Read access to the single Notification_Setting__mdt Custom Metadata Type. Rows are told apart by
 * Type__c so the framework uses one metadata type instead of seven:
 *
 *   Type__c         Key__c         Value__c            Value2__c        Source / Channel   Number1 / Number2
 *   KillSwitch      -              reason              -                optional filters   -
 *   RetryPolicy     -              "1,5,15,60"         -                Channel            jitter %, max attempts
 *   MergeToken      token name     description         -                -                  -
 *   LocaleAlias     alias          locale              -                -                  -
 *   ChannelAdapter  -              adapter class       -                Channel            batch size, max send calls
 *   SourceCapability -             allowed channels    -                Source             max payload bytes
 *   EventRegistry   event type     definition key      resolver key     Source             -
 *
 * Only rows with Active__c = true are used. Test classes can replace the data through
 * settingsOverride because Custom Metadata records cannot be inserted in tests.
 */
public with sharing class NotificationConfig {
    public static final String KILL_SWITCH = 'KillSwitch';
    public static final String RETRY_POLICY = 'RetryPolicy';
    public static final String MERGE_TOKEN = 'MergeToken';
    public static final String LOCALE_ALIAS = 'LocaleAlias';
    public static final String CHANNEL_ADAPTER = 'ChannelAdapter';
    public static final String SOURCE_CAPABILITY = 'SourceCapability';
    public static final String EVENT_REGISTRY = 'EventRegistry';

    public static final List<Integer> DEFAULT_RETRY_MINUTES = new List<Integer>{ 1, 5, 15, 60 };

    @TestVisible
    private static List<Notification_Setting__mdt> settingsOverride;

    /** Active settings of one type. */
    public static List<Notification_Setting__mdt> byType(String type) {
        List<Notification_Setting__mdt> all = settingsOverride != null
            ? settingsOverride
            : Notification_Setting__mdt.getAll().values();
        List<Notification_Setting__mdt> out = new List<Notification_Setting__mdt>();
        for (Notification_Setting__mdt s : all) {
            if (s.Type__c == type && s.Active__c == true) {
                out.add(s);
            }
        }
        return out;
    }

    /** Normalizes "pt-BR" to "pt_BR" and applies an active locale alias if one is configured. */
    public static String normalizeLocale(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String s = raw.trim().replace('-', '_');
        for (Notification_Setting__mdt a : byType(LOCALE_ALIAS)) {
            if (String.isNotBlank(a.Key__c) && String.isNotBlank(a.Value__c)
                && a.Key__c.replace('-', '_').equalsIgnoreCase(s)) {
                return a.Value__c.trim();
            }
        }
        return s;
    }

    /** Active registered merge tokens. An empty set means no registry is configured (no restriction). */
    public static Set<String> allowedTokens() {
        Set<String> out = new Set<String>();
        for (Notification_Setting__mdt t : byType(MERGE_TOKEN)) {
            if (String.isNotBlank(t.Key__c)) {
                out.add(t.Key__c.trim());
            }
        }
        return out;
    }

    /** True when an active kill switch matches. A blank source or channel on the switch matches anything. */
    public static Boolean isKilled(String sourceApplication, String channel) {
        for (Notification_Setting__mdt k : byType(KILL_SWITCH)) {
            Boolean sourceMatches = String.isBlank(k.Source_Application__c) || k.Source_Application__c == sourceApplication;
            Boolean channelMatches = String.isBlank(k.Channel__c) || k.Channel__c == channel;
            if (sourceMatches && channelMatches) {
                return true;
            }
        }
        return false;
    }

    /** Retry delays in minutes for a channel; falls back to 1, 5, 15, 60. */
    public static List<Integer> retryOffsetsMinutes(String channel) {
        for (Notification_Setting__mdt p : byType(RETRY_POLICY)) {
            if (p.Channel__c == channel && String.isNotBlank(p.Value__c)) {
                List<Integer> out = new List<Integer>();
                for (String s : p.Value__c.split(',')) {
                    if (String.isNotBlank(s) && s.trim().isNumeric()) {
                        out.add(Integer.valueOf(s.trim()));
                    }
                }
                if (!out.isEmpty()) {
                    return out;
                }
            }
        }
        return DEFAULT_RETRY_MINUTES.clone();
    }
}
