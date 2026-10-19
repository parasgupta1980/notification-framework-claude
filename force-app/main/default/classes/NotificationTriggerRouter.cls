/** One thin entry point per trigger; keeps all logic in testable handler classes. */
public without sharing class NotificationTriggerRouter {
    public static void routeRequest() {
        NotificationKeyHandler.request(
            (List<Notification_Request__c>) Trigger.new, (Map<Id, Notification_Request__c>) Trigger.oldMap
        );
    }

    public static void routeDelivery() {
        NotificationKeyHandler.delivery(
            (List<Notification_Delivery__c>) Trigger.new, (Map<Id, Notification_Delivery__c>) Trigger.oldMap
        );
    }

    public static void routeTranslation() {
        if (Trigger.isDelete) {
            NotificationTranslationHandler.beforeDelete((List<Notification_Translation__c>) Trigger.old);
        } else {
            NotificationTranslationHandler.beforeWrite(
                (List<Notification_Translation__c>) Trigger.new, (Map<Id, Notification_Translation__c>) Trigger.oldMap
            );
        }
    }

    public static void routeDefinition() {
        if (Trigger.isDelete) {
            NotificationDefinitionHandler.beforeDelete((List<Notification_Definition__c>) Trigger.old);
        } else if (Trigger.isInsert) {
            NotificationDefinitionHandler.beforeInsert((List<Notification_Definition__c>) Trigger.new);
        } else {
            NotificationDefinitionHandler.beforeUpdate(
                (List<Notification_Definition__c>) Trigger.new, (Map<Id, Notification_Definition__c>) Trigger.oldMap
            );
        }
    }
}
