@IsTest
private class NotificationKeysTest {
    @IsTest
    static void keysAreDeterministic64CharHexAndCollisionSafe() {
        String a = NotificationKeys.eventKey('SAP', 'E1');
        System.assertEquals(64, a.length());
        System.assertEquals(a, NotificationKeys.eventKey('SAP', 'E1'));
        System.assertNotEquals(a, NotificationKeys.eventKey('SAP', 'E2'));
        System.assertNotEquals(NotificationKeys.hash(new List<String>{ 'a|b', 'c' }), NotificationKeys.hash(new List<String>{ 'a', 'b|c' }));
        System.assertNotEquals(NotificationKeys.hash(new List<String>{ null, 'x' }), NotificationKeys.hash(new List<String>{ 'x', null }));
        System.assertEquals(64, NotificationKeys.payloadHash(null).length());
        System.assertEquals(64, NotificationKeys.deliveryKey(a, 'def', '005000000000001', 'Bell', 'US').length());
        System.assertEquals(64, NotificationKeys.definitionLocaleKey(null, 'en_US').length());
    }

    @IsTest
    static void requestKeysAreFilledAndDuplicatesAreRejected() {
        Notification_Definition__c d = NotificationTestDataFactory.createDefinition('k1', '/x');
        Notification_Request__c r1 = new Notification_Request__c(
            Source_Application__c = 'SAP', Business_Event_Id__c = 'E1', Definition__c = d.Id, Context_Json__c = '{"a":1}', Status__c = 'Accepted'
        );
        insert r1;
        r1 = [SELECT EventKey__c, Payload_Hash__c FROM Notification_Request__c WHERE Id = :r1.Id];
        System.assertEquals(NotificationKeys.eventKey('SAP', 'E1'), r1.EventKey__c);
        System.assertEquals(NotificationKeys.payloadHash('{"a":1}'), r1.Payload_Hash__c);

        Notification_Request__c dup = new Notification_Request__c(
            Source_Application__c = 'SAP', Business_Event_Id__c = 'E1', Definition__c = d.Id, Context_Json__c = '{"a":2}', Status__c = 'Accepted'
        );
        Database.SaveResult sr = Database.insert(dup, false);
        System.assert(!sr.isSuccess(), 'same event key must be rejected by the unique key');
    }

    @IsTest
    static void requestIdentityAndPayloadAreImmutable() {
        Notification_Definition__c d = NotificationTestDataFactory.createDefinition('k2', '/x');
        Notification_Request__c r = NotificationTestDataFactory.createRequest(d.Id, 'E9', '{"a":1}');
        r.Context_Json__c = '{"a":2}';
        System.assert(!Database.update(r, false).isSuccess());
        r = [SELECT Status__c FROM Notification_Request__c WHERE Id = :r.Id];
        r.Status__c = 'Completed';
        System.assert(Database.update(r, false).isSuccess(), 'status can still move');
    }

    @IsTest
    static void deliveryKeyIsFilledAndUniquePerRecipientChannelAndStore() {
        User u = NotificationTestDataFactory.createUser('key');
        Notification_Definition__c d = NotificationTestDataFactory.createDefinition('k3', '/x');
        Notification_Request__c r = NotificationTestDataFactory.createRequest(d.Id, 'E3', '{}');
        Notification_Delivery__c d1 = new Notification_Delivery__c(
            Request__c = r.Id, Recipient_User__c = u.Id, Channel__c = 'Bell', Status__c = 'Visible', Store_Key__c = 'US'
        );
        insert d1;
        d1 = [SELECT DeliveryKey__c, Request__r.EventKey__c FROM Notification_Delivery__c WHERE Id = :d1.Id];
        System.assertEquals(
            NotificationKeys.deliveryKey(d1.Request__r.EventKey__c, 'k3', String.valueOf(u.Id), 'Bell', 'US'), d1.DeliveryKey__c
        );
        Notification_Delivery__c dup = new Notification_Delivery__c(
            Request__c = r.Id, Recipient_User__c = u.Id, Channel__c = 'Bell', Status__c = 'Visible', Store_Key__c = 'US'
        );
        System.assert(!Database.insert(dup, false).isSuccess(), 'exactly-once creation by unique key');
        Notification_Delivery__c email = new Notification_Delivery__c(
            Request__c = r.Id, Recipient_User__c = u.Id, Channel__c = 'Email', Status__c = 'Pending', Store_Key__c = 'US'
        );
        System.assert(Database.insert(email, false).isSuccess(), 'a different channel is a different delivery');
    }

    @IsTest
    static void deliveryIdentityCannotBeRewrittenButReadStateCanChange() {
        User u = NotificationTestDataFactory.createUser('imm');
        User v = NotificationTestDataFactory.createUser('imm2');
        Notification_Definition__c d = NotificationTestDataFactory.createDefinition('k4', '/x');
        Notification_Request__c r = NotificationTestDataFactory.createRequest(d.Id, 'E4', '{}');
        Notification_Delivery__c del = NotificationTestDataFactory.createBell(r.Id, u.Id, 'fixedkey', 'US', Datetime.now());
        del.ReadAt__c = Datetime.now();
        System.assert(Database.update(del, false).isSuccess());
        del.Recipient_User__c = v.Id;
        System.assert(!Database.update(del, false).isSuccess(), 'reassigning the recipient is blocked');
        del = [SELECT Recipient_User__c, DeliveryKey__c FROM Notification_Delivery__c WHERE Id = :del.Id];
        del.DeliveryKey__c = 'other';
        System.assert(!Database.update(del, false).isSuccess());
        del = [SELECT Recipient_User__c FROM Notification_Delivery__c WHERE Id = :del.Id];
        del.Recipient_User__c = null;
        System.assert(Database.update(del, false).isSuccess(), 'clearing the recipient is allowed (user deletion)');
    }
}
