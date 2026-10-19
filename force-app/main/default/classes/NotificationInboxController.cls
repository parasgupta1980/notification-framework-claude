/**
 * Bell inbox API (design section 6). The user always comes from the session and is never
 * accepted as a parameter. Customers reach Delivery rows only through this class.
 */
public with sharing class NotificationInboxController {
    private static final Integer DEFAULT_PAGE = 20;

    @AuraEnabled
    public static NotificationInboxDto.Summary getSummary(String storeKey) {
        String store = NotificationStoreAccess.validate(storeKey);
        Id uid = UserInfo.getUserId();
        NotificationInboxDto.Summary s = new NotificationInboxDto.Summary();
        Integer unread = NotificationInboxSelector.countUnread(uid, store);
        s.unreadCountCapped = unread > NotificationInboxSelector.UNREAD_CAP;
        s.unreadCount = Math.min(unread, NotificationInboxSelector.UNREAD_CAP);
        s.unseenCount = Math.min(NotificationInboxSelector.countUnseen(uid, store), NotificationInboxSelector.UNREAD_CAP);
        s.latestVisibleAt = NotificationInboxSelector.latestVisibleAt(uid, store);
        return s;
    }

    @AuraEnabled
    public static NotificationInboxDto.InboxPage listMine(String storeKey, String lang, String cursor, Integer pageSize) {
        String store = NotificationStoreAccess.validate(storeKey);
        Integer size = pageSize == null ? DEFAULT_PAGE : pageSize;
        Datetime cursorAt;
        Id cursorId;
        if (String.isNotBlank(cursor)) {
            List<String> parts = cursor.split('\\|');
            if (parts.size() != 2) {
                throw new AuraHandledException(Label.Nimbus_Notif_Invalid_Cursor);
            }
            try {
                cursorAt = Datetime.newInstance(Long.valueOf(parts[0]));
                cursorId = Id.valueOf(parts[1]);
            } catch (Exception e) {
                throw new AuraHandledException(Label.Nimbus_Notif_Invalid_Cursor);
            }
        }
        List<Notification_Delivery__c> rows = NotificationInboxSelector.page(
            UserInfo.getUserId(), store, cursorAt, cursorId, size
        );
        Integer limitSize = Math.min(Math.max(size, 1), NotificationInboxSelector.MAX_PAGE);
        NotificationInboxDto.InboxPage page = new NotificationInboxDto.InboxPage();
        if (rows.size() > limitSize) {
            page.hasMore = true;
            rows.remove(rows.size() - 1);
            Notification_Delivery__c lastRow = rows[rows.size() - 1];
            page.nextCursor = String.valueOf(lastRow.Visible_At__c.getTime()) + '|' + lastRow.Id;
        }
        page.items = NotificationRenderer.render(rows, lang);
        return page;
    }

    @AuraEnabled
    public static Integer markRead(List<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return 0;
        }
        List<Notification_Delivery__c> toUpdate = new List<Notification_Delivery__c>();
        for (Notification_Delivery__c d : NotificationInboxSelector.ownedByUser(UserInfo.getUserId(), new Set<Id>(ids))) {
            if (d.ReadAt__c == null) {
                toUpdate.add(new Notification_Delivery__c(Id = d.Id, ReadAt__c = Datetime.now()));
            }
        }
        updateAsSystem(toUpdate);
        return toUpdate.size();
    }

    @AuraEnabled
    public static Integer markAllRead(String storeKey, Datetime cutoff) {
        String store = NotificationStoreAccess.validate(storeKey);
        Datetime upTo = cutoff == null ? Datetime.now() : cutoff;
        List<Notification_Delivery__c> toUpdate = new List<Notification_Delivery__c>();
        for (Notification_Delivery__c d : NotificationInboxSelector.unreadUpTo(UserInfo.getUserId(), store, upTo)) {
            toUpdate.add(new Notification_Delivery__c(Id = d.Id, ReadAt__c = Datetime.now()));
        }
        updateAsSystem(toUpdate);
        return toUpdate.size();
    }

    @AuraEnabled
    public static Integer markSeen(Datetime cutoff) {
        Datetime upTo = cutoff == null ? Datetime.now() : cutoff;
        List<Notification_Delivery__c> toUpdate = new List<Notification_Delivery__c>();
        for (Notification_Delivery__c d : NotificationInboxSelector.unseenUpTo(UserInfo.getUserId(), upTo)) {
            toUpdate.add(new Notification_Delivery__c(Id = d.Id, SeenAt__c = Datetime.now()));
        }
        updateAsSystem(toUpdate);
        return toUpdate.size();
    }

    /** Only ever called with rows already proven to belong to the current user. */
    private static void updateAsSystem(List<Notification_Delivery__c> rows) {
        if (!rows.isEmpty()) {
            NotificationInboxSelector.updateRows(rows);
        }
    }
}
