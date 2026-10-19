trigger NotificationRequestTrigger on Notification_Request__c (before insert, before update) {
    NotificationTriggerRouter.routeRequest();
}
