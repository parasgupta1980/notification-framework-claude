/**
 * Fills and protects the identity keys on Request, Delivery and Translation.
 * Keys are filled only when blank on insert, so callers (ingress, resolver) that already computed
 * them through NotificationKeys keep control. Once stored, identity fields cannot be changed.
 * Runs without sharing: integrity checks must see every row.
 */
public without sharing class NotificationKeyHandler {
    public static void request(List<Notification_Request__c> rows, Map<Id, Notification_Request__c> oldMap) {
        for (Notification_Request__c r : rows) {
            if (oldMap == null) {
                if (String.isBlank(r.EventKey__c) && String.isNotBlank(r.Source_Application__c)
                    && String.isNotBlank(r.Business_Event_Id__c)) {
                    r.EventKey__c = NotificationKeys.eventKey(r.Source_Application__c, r.Business_Event_Id__c);
                }
                if (String.isBlank(r.Payload_Hash__c)) {
                    r.Payload_Hash__c = NotificationKeys.payloadHash(r.Context_Json__c);
                }
            } else {
                Notification_Request__c o = oldMap.get(r.Id);
                if (r.Source_Application__c != o.Source_Application__c
                    || r.Business_Event_Id__c != o.Business_Event_Id__c
                    || r.EventKey__c != o.EventKey__c
                    || r.Definition__c != o.Definition__c
                    || r.Context_Json__c != o.Context_Json__c
                    || r.Payload_Hash__c != o.Payload_Hash__c) {
                    r.addError('A request\'s event identity, pinned definition and payload cannot be changed.');
                }
            }
        }
    }

    public static void delivery(List<Notification_Delivery__c> rows, Map<Id, Notification_Delivery__c> oldMap) {
        if (oldMap != null) {
            for (Notification_Delivery__c d : rows) {
                Notification_Delivery__c o = oldMap.get(d.Id);
                Boolean recipientReassigned = d.Recipient_User__c != o.Recipient_User__c && d.Recipient_User__c != null;
                if (d.Request__c != o.Request__c || d.Channel__c != o.Channel__c
                    || d.DeliveryKey__c != o.DeliveryKey__c || recipientReassigned) {
                    d.addError('A delivery\'s request, recipient, channel and key cannot be changed.');
                }
            }
            return;
        }
        Set<Id> requestIds = new Set<Id>();
        for (Notification_Delivery__c d : rows) {
            if (String.isBlank(d.DeliveryKey__c) && d.Request__c != null) {
                requestIds.add(d.Request__c);
            }
        }
        if (requestIds.isEmpty()) {
            return;
        }
        Map<Id, Notification_Request__c> requests = new Map<Id, Notification_Request__c>([
            SELECT Id, EventKey__c, Definition__r.Key__c
            FROM Notification_Request__c
            WHERE Id IN :requestIds
        ]);
        for (Notification_Delivery__c d : rows) {
            Notification_Request__c req = requests.get(d.Request__c);
            if (String.isNotBlank(d.DeliveryKey__c) || req == null) {
                continue;
            }
            Id recipient = d.Recipient_User__c != null ? d.Recipient_User__c : d.Recipient_Contact__c;
            d.DeliveryKey__c = NotificationKeys.deliveryKey(
                req.EventKey__c, req.Definition__r?.Key__c,
                recipient == null ? null : String.valueOf(recipient), d.Channel__c, d.Store_Key__c
            );
        }
    }
}
