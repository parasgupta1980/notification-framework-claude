trigger NotificationDeliveryTrigger on Notification_Delivery__c (before insert, before update) {
    NotificationTriggerRouter.routeDelivery();
}
