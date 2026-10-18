/**
 * Renders Bell rows at read time (design section 6): Delivery -> Request -> Definition ->
 * Translation for the chosen locale. A whole bundle is used or English is used as a whole;
 * languages are never mixed inside one notification.
 */
public with sharing class NotificationRenderer {
    public static final String FALLBACK_LOCALE = 'en_US';
    private static final Pattern TOKEN = Pattern.compile('\\{\\{\\s*([A-Za-z0-9_]+)\\s*\\}\\}');

    /** Candidate locales in priority order: exact, language-only, then English. */
    public static List<String> candidates(String lang) {
        List<String> out = new List<String>();
        if (String.isNotBlank(lang)) {
            String normalized = lang.replace('-', '_');
            out.add(normalized);
            if (normalized.contains('_')) {
                out.add(normalized.substringBefore('_'));
            }
        }
        out.add(FALLBACK_LOCALE);
        out.add('en');
        return out;
    }

    public static List<NotificationInboxDto.Item> render(List<Notification_Delivery__c> rows, String lang) {
        List<NotificationInboxDto.Item> items = new List<NotificationInboxDto.Item>();
        if (rows.isEmpty()) {
            return items;
        }
        List<String> order = candidates(lang);
        Set<Id> defIds = new Set<Id>();
        for (Notification_Delivery__c r : rows) {
            if (r.Request__r?.Definition__c != null) {
                defIds.add(r.Request__r.Definition__c);
            }
        }
        Map<Id, Notification_Definition__c> defs = NotificationInboxSelector.definitions(defIds);
        Map<String, Notification_Translation__c> byKey = new Map<String, Notification_Translation__c>();
        for (Notification_Translation__c t : NotificationInboxSelector.translations(defIds, new Set<String>(order))) {
            byKey.put(t.Definition__c + '|' + t.Locale__c, t);
        }

        for (Notification_Delivery__c r : rows) {
            NotificationInboxDto.Item item = new NotificationInboxDto.Item();
            item.id = r.Id;
            item.visibleAt = r.Visible_At__c;
            item.isRead = r.ReadAt__c != null;
            Id defId = r.Request__r?.Definition__c;
            Notification_Translation__c t = null;
            if (defId != null) {
                for (String loc : order) {
                    t = byKey.get(defId + '|' + loc);
                    if (t != null) {
                        item.renderedLocale = loc;
                        break;
                    }
                }
            }
            if (t == null) {
                item.unavailable = true;
                item.title = Label.Nimbus_Notif_Unavailable;
                items.add(item);
                continue;
            }
            Map<String, Object> ctx = parseContext(r.Request__r.Context_Json__c);
            item.unavailable = false;
            item.title = merge(t.Title__c, ctx);
            item.message = merge(t.Message__c, ctx);
            item.actionLabel = t.Action_Label__c;
            item.targetUrl = NotificationTargetValidator.safeOrNull(
                merge(defs.get(defId)?.Target_Route__c, ctx)
            );
            items.add(item);
        }
        return items;
    }

    private static Map<String, Object> parseContext(String json) {
        if (String.isBlank(json)) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) System.JSON.deserializeUntyped(json);
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    /** Replaces {{token}} with scalar context values; unknown tokens render empty. */
    @TestVisible
    private static String merge(String template, Map<String, Object> ctx) {
        if (String.isBlank(template)) {
            return template;
        }
        Matcher m = TOKEN.matcher(template);
        String out = '';
        Integer last = 0;
        while (m.find()) {
            out += template.substring(last, m.start());
            Object v = ctx.get(m.group(1));
            out += (v == null || v instanceof List<Object> || v instanceof Map<String, Object>) ? '' : String.valueOf(v);
            last = m.end();
        }
        return out + template.substring(last);
    }
}
