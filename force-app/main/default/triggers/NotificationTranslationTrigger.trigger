trigger NotificationTranslationTrigger on Notification_Translation__c (before insert, before update, before delete) {
    NotificationTriggerRouter.routeTranslation();
}
