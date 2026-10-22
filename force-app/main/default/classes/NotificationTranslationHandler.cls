/**
 * Translation rules: normalizes the locale, fills the unique Definition + Locale key, and keeps
 * translations of Active or Retired definitions frozen (an edit means a new definition record).
 * Runs without sharing so the definition status check sees every row.
 */
public without sharing class NotificationTranslationHandler {
    public static void beforeWrite(List<Notification_Translation__c> rows, Map<Id, Notification_Translation__c> oldMap) {
        for (Notification_Translation__c t : rows) {
            String loc = NotificationConfig.normalizeLocale(t.Locale__c);
            if (loc != null) {
                t.Locale__c = loc;
            }
            if (t.Definition__c != null && loc != null) {
                t.DefinitionLocaleKey__c = NotificationKeys.definitionLocaleKey(t.Definition__c, loc);
            }
        }
        if (NotificationGuard.isBypassed()) {
            return;
        }
        Set<Id> defIds = new Set<Id>();
        for (Notification_Translation__c t : rows) {
            if (t.Definition__c != null) {
                defIds.add(t.Definition__c);
            }
            Notification_Translation__c o = oldMap == null ? null : oldMap.get(t.Id);
            if (o != null && o.Definition__c != null) {
                defIds.add(o.Definition__c);
            }
        }
        Map<Id, String> statuses = statuses(defIds);
        for (Notification_Translation__c t : rows) {
            Notification_Translation__c o = oldMap == null ? null : oldMap.get(t.Id);
            if (isFrozen(statuses, t.Definition__c) || (o != null && isFrozen(statuses, o.Definition__c))) {
                t.addError('Translations of an Active or Retired definition cannot be changed. Create a new definition.');
            }
        }
    }

    public static void beforeDelete(List<Notification_Translation__c> rows) {
        if (NotificationGuard.isBypassed()) {
            return;
        }
        Set<Id> defIds = new Set<Id>();
        for (Notification_Translation__c t : rows) {
            if (t.Definition__c != null) {
                defIds.add(t.Definition__c);
            }
        }
        Map<Id, String> statuses = statuses(defIds);
        for (Notification_Translation__c t : rows) {
            if (isFrozen(statuses, t.Definition__c)) {
                t.addError('Translations of an Active or Retired definition cannot be deleted.');
            }
        }
    }

    private static Map<Id, String> statuses(Set<Id> defIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (defIds.isEmpty()) {
            return out;
        }
        for (Notification_Definition__c d : [SELECT Id, Status__c FROM Notification_Definition__c WHERE Id IN :defIds]) {
            out.put(d.Id, d.Status__c);
        }
        return out;
    }

    private static Boolean isFrozen(Map<Id, String> statuses, Id definitionId) {
        String s = definitionId == null ? null : statuses.get(definitionId);
        return s == NotificationDefinitionHandler.ACTIVE || s == NotificationDefinitionHandler.RETIRED;
    }
}
