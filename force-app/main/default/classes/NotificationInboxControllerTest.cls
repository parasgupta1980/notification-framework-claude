@IsTest
private class NotificationInboxControllerTest {
    private static User owner;
    private static User other;
    private static Notification_Definition__c def;
    private static Notification_Request__c req;

    private static void setup() {
        owner = NotificationTestDataFactory.createUser('own');
        other = NotificationTestDataFactory.createUser('oth');
        def = NotificationTestDataFactory.createDefinition('order_status', '/orders/{{orderId}}');
        NotificationTestDataFactory.addTranslation(def.Id, 'en_US', 'Order {{orderId}} shipped', 'Your order is on the way.');
        NotificationTestDataFactory.addTranslation(def.Id, 'de', 'Bestellung {{orderId}} versendet', 'Ihre Bestellung ist unterwegs.');
        req = NotificationTestDataFactory.createRequest(def.Id, 'e1', '{"orderId":"A100"}');
    }

    @IsTest
    static void summaryCountsOnlyCurrentUsersUnreadRowsInStore() {
        setup();
        Datetime now = Datetime.now();
        NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k1', 'US', now.addMinutes(-3));
        NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k2', 'EU', now.addMinutes(-2)); // other store
        NotificationTestDataFactory.createBell(req.Id, other.Id, 'k3', 'US', now.addMinutes(-1)); // other user

        System.runAs(owner) {
            NotificationInboxDto.Summary s = NotificationInboxController.getSummary('US');
            System.assertEquals(1, s.unreadCount);
            System.assertEquals(false, s.unreadCountCapped);
        }
    }

    @IsTest
    static void listReturnsNewestFirstRenderedInChosenLanguageWithFallback() {
        setup();
        Datetime now = Datetime.now();
        NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k1', 'US', now.addMinutes(-10));
        NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k2', 'US', now.addMinutes(-1));

        System.runAs(owner) {
            NotificationInboxDto.InboxPage de = NotificationInboxController.listMine('US', 'de', null, 20);
            System.assertEquals(2, de.items.size());
            System.assertEquals('Bestellung A100 versendet', de.items[0].title);
            System.assertEquals('/orders/A100', de.items[0].targetUrl);
            System.assert(de.items[0].visibleAt > de.items[1].visibleAt, 'newest first');

            NotificationInboxDto.InboxPage fr = NotificationInboxController.listMine('US', 'fr', null, 20);
            System.assertEquals('Order A100 shipped', fr.items[0].title, 'whole-bundle English fallback');
            System.assertEquals('en_US', fr.items[0].renderedLocale);
        }
    }

    @IsTest
    static void paginationUsesKeysetCursor() {
        setup();
        Datetime now = Datetime.now();
        for (Integer i = 0; i < 5; i++) {
            NotificationTestDataFactory.createBell(req.Id, owner.Id, 'p' + i, 'US', now.addMinutes(-i));
        }
        System.runAs(owner) {
            NotificationInboxDto.InboxPage first = NotificationInboxController.listMine('US', 'en_US', null, 2);
            System.assertEquals(2, first.items.size());
            System.assertEquals(true, first.hasMore);
            NotificationInboxDto.InboxPage second = NotificationInboxController.listMine('US', 'en_US', first.nextCursor, 2);
            System.assertEquals(2, second.items.size());
            NotificationInboxDto.InboxPage third = NotificationInboxController.listMine('US', 'en_US', second.nextCursor, 2);
            System.assertEquals(1, third.items.size());
            System.assertEquals(false, third.hasMore);
            Set<Id> seen = new Set<Id>();
            for (NotificationInboxDto.InboxPage p : new List<NotificationInboxDto.InboxPage>{ first, second, third }) {
                for (NotificationInboxDto.Item i : p.items) {
                    System.assert(seen.add(i.id), 'no duplicates across pages');
                }
            }
        }
    }

    @IsTest
    static void markReadIgnoresRowsOwnedByOtherUsers() {
        setup();
        Notification_Delivery__c mine = NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k1', 'US', Datetime.now().addMinutes(-2));
        Notification_Delivery__c theirs = NotificationTestDataFactory.createBell(req.Id, other.Id, 'k2', 'US', Datetime.now().addMinutes(-1));

        System.runAs(owner) {
            Integer changed = NotificationInboxController.markRead(new List<Id>{ mine.Id, theirs.Id });
            System.assertEquals(1, changed);
        }
        System.assertNotEquals(null, [SELECT ReadAt__c FROM Notification_Delivery__c WHERE Id = :mine.Id].ReadAt__c);
        System.assertEquals(null, [SELECT ReadAt__c FROM Notification_Delivery__c WHERE Id = :theirs.Id].ReadAt__c);
    }

    @IsTest
    static void markAllReadRespectsCutoffSoLaterArrivalsStayUnread() {
        setup();
        Datetime now = Datetime.now();
        Notification_Delivery__c early = NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k1', 'US', now.addMinutes(-10));
        Notification_Delivery__c late = NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k2', 'US', now.addMinutes(5));

        System.runAs(owner) {
            NotificationInboxController.markAllRead('US', now);
        }
        System.assertNotEquals(null, [SELECT ReadAt__c FROM Notification_Delivery__c WHERE Id = :early.Id].ReadAt__c);
        System.assertEquals(null, [SELECT ReadAt__c FROM Notification_Delivery__c WHERE Id = :late.Id].ReadAt__c);
    }

    @IsTest
    static void markSeenOnlyTouchesCurrentUser() {
        setup();
        Notification_Delivery__c mine = NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k1', 'US', Datetime.now().addMinutes(-2));
        Notification_Delivery__c theirs = NotificationTestDataFactory.createBell(req.Id, other.Id, 'k2', 'US', Datetime.now().addMinutes(-2));
        System.runAs(owner) {
            NotificationInboxController.markSeen(Datetime.now());
        }
        System.assertNotEquals(null, [SELECT SeenAt__c FROM Notification_Delivery__c WHERE Id = :mine.Id].SeenAt__c);
        System.assertEquals(null, [SELECT SeenAt__c FROM Notification_Delivery__c WHERE Id = :theirs.Id].SeenAt__c);
    }

    @IsTest
    static void expiredAndSuppressedRowsAreNotShown() {
        setup();
        Notification_Delivery__c expired = NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k1', 'US', Datetime.now().addDays(-2));
        expired.Expires_At__c = Datetime.now().addDays(-1);
        update expired;
        Notification_Delivery__c suppressed = NotificationTestDataFactory.createBell(req.Id, owner.Id, 'k2', 'US', Datetime.now().addMinutes(-1));
        suppressed.Status__c = 'Suppressed';
        update suppressed;

        System.runAs(owner) {
            System.assertEquals(0, NotificationInboxController.getSummary('US').unreadCount);
            System.assertEquals(0, NotificationInboxController.listMine('US', 'en_US', null, 20).items.size());
        }
    }

    @IsTest
    static void invalidStoreKeyAndCursorAreRejected() {
        setup();
        System.runAs(owner) {
            try {
                NotificationInboxController.getSummary('US; DROP');
                System.assert(false, 'expected rejection');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            try {
                NotificationInboxController.listMine('US', 'en_US', 'garbage', 20);
                System.assert(false, 'expected rejection');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @IsTest
    static void missingTranslationRendersUnavailable() {
        setup();
        Notification_Definition__c bare = NotificationTestDataFactory.createDefinition('no_translation', '/x');
        Notification_Request__c r2 = NotificationTestDataFactory.createRequest(bare.Id, 'e2', '{}');
        NotificationTestDataFactory.createBell(r2.Id, owner.Id, 'k1', 'US', Datetime.now().addMinutes(-1));
        System.runAs(owner) {
            NotificationInboxDto.Item item = NotificationInboxController.listMine('US', 'en_US', null, 20).items[0];
            System.assertEquals(true, item.unavailable);
            System.assertEquals(null, item.targetUrl);
        }
    }

    @IsTest
    static void targetValidatorRejectsUnsafeRoutes() {
        for (String bad : new List<String>{ null, '', 'https://evil.example', '//evil.example', 'javascript:alert(1)', '/a\\b', '/%2F%2Fevil', 'orders/1' }) {
            System.assertEquals(false, NotificationTargetValidator.isSafe(bad), 'should reject: ' + bad);
        }
        System.assertEquals(true, NotificationTargetValidator.isSafe('/orders/42?tab=items'));
    }

    @IsTest
    static void mergeLeavesUnknownTokensEmptyAndIgnoresNestedValues() {
        Map<String, Object> ctx = new Map<String, Object>{ 'a' => 'X', 'n' => 5, 'obj' => new Map<String, Object>() };
        System.assertEquals('X-5--', NotificationRenderer.mergeTokens('{{a}}-{{n}}-{{missing}}-{{obj}}', ctx));
    }
}
