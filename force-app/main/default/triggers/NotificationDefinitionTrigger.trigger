trigger NotificationDefinitionTrigger on Notification_Definition__c (before insert, before update, before delete) {
    NotificationTriggerRouter.routeDefinition();
}
