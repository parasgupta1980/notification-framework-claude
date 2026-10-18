/**
 * Narrow privileged selector for the bell inbox. Customers have no object permissions
 * on Notification_Delivery__c (design section 9), so this runs without sharing and
 * is safe ONLY because every query is hard-scoped to the running user's Id and
 * returns an allowlisted set of fields.
 */
public without sharing class NotificationInboxSelector {
    public static final Integer UNREAD_CAP = 99;
    public static final Integer MAX_PAGE = 50;

    private static final String BELL = 'Bell';
    private static final String VISIBLE = 'Visible';

    public static Integer countUnread(Id userId, String storeKey) {
        Datetime nowDt = Datetime.now();
        Integer capPlusOne = UNREAD_CAP + 1;
        return [
            SELECT COUNT() FROM Notification_Delivery__c
            WHERE Recipient_User__c = :userId AND Channel__c = :BELL AND Status__c = :VISIBLE
              AND ReadAt__c = NULL AND (Expires_At__c = NULL OR Expires_At__c > :nowDt)
              AND (Store_Key__c = NULL OR Store_Key__c = :storeKey)
            LIMIT :capPlusOne
        ];
    }

    public static Integer countUnseen(Id userId, String storeKey) {
        Datetime nowDt = Datetime.now();
        Integer capPlusOne = UNREAD_CAP + 1;
        return [
            SELECT COUNT() FROM Notification_Delivery__c
            WHERE Recipient_User__c = :userId AND Channel__c = :BELL AND Status__c = :VISIBLE
              AND SeenAt__c = NULL AND (Expires_At__c = NULL OR Expires_At__c > :nowDt)
              AND (Store_Key__c = NULL OR Store_Key__c = :storeKey)
            LIMIT :capPlusOne
        ];
    }

    public static Datetime latestVisibleAt(Id userId, String storeKey) {
        Datetime nowDt = Datetime.now();
        List<Notification_Delivery__c> rows = [
            SELECT Visible_At__c FROM Notification_Delivery__c
            WHERE Recipient_User__c = :userId AND Channel__c = :BELL AND Status__c = :VISIBLE
              AND (Expires_At__c = NULL OR Expires_At__c > :nowDt)
              AND (Store_Key__c = NULL OR Store_Key__c = :storeKey)
            ORDER BY Visible_At__c DESC, Id DESC LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Visible_At__c;
    }

    /** Keyset pagination: rows strictly older than (cursorAt, cursorId). Fetches limit + 1. */
    public static List<Notification_Delivery__c> page(
        Id userId, String storeKey, Datetime cursorAt, Id cursorId, Integer pageSize
    ) {
        Integer lim = Math.min(Math.max(pageSize, 1), MAX_PAGE) + 1;
        Datetime now = Datetime.now();
        if (cursorAt == null) {
            return [
                SELECT Id, Request__r.Definition__c, Request__r.Context_Json__c, Visible_At__c, ReadAt__c
                FROM Notification_Delivery__c
                WHERE Recipient_User__c = :userId AND Channel__c = :BELL AND Status__c = :VISIBLE
                  AND (Expires_At__c = NULL OR Expires_At__c > :now)
                  AND (Store_Key__c = NULL OR Store_Key__c = :storeKey)
                ORDER BY Visible_At__c DESC, Id DESC LIMIT :lim
            ];
        }
        return [
            SELECT Id, Request__r.Definition__c, Request__r.Context_Json__c, Visible_At__c, ReadAt__c
            FROM Notification_Delivery__c
            WHERE Recipient_User__c = :userId AND Channel__c = :BELL AND Status__c = :VISIBLE
              AND (Expires_At__c = NULL OR Expires_At__c > :now)
              AND (Store_Key__c = NULL OR Store_Key__c = :storeKey)
              AND (Visible_At__c < :cursorAt OR (Visible_At__c = :cursorAt AND Id < :cursorId))
            ORDER BY Visible_At__c DESC, Id DESC LIMIT :lim
        ];
    }

    /** Rows the user owns among the supplied ids. Foreign ids are silently dropped. */
    public static List<Notification_Delivery__c> ownedByUser(Id userId, Set<Id> ids) {
        return [
            SELECT Id, ReadAt__c, SeenAt__c FROM Notification_Delivery__c
            WHERE Id IN :ids AND Recipient_User__c = :userId AND Channel__c = :BELL
        ];
    }

    public static List<Notification_Delivery__c> unreadUpTo(Id userId, String storeKey, Datetime cutoff) {
        return [
            SELECT Id, ReadAt__c FROM Notification_Delivery__c
            WHERE Recipient_User__c = :userId AND Channel__c = :BELL AND Status__c = :VISIBLE
              AND ReadAt__c = NULL AND Visible_At__c <= :cutoff
              AND (Store_Key__c = NULL OR Store_Key__c = :storeKey)
            LIMIT 2000
        ];
    }

    public static List<Notification_Delivery__c> unseenUpTo(Id userId, Datetime cutoff) {
        return [
            SELECT Id, SeenAt__c FROM Notification_Delivery__c
            WHERE Recipient_User__c = :userId AND Channel__c = :BELL AND Status__c = :VISIBLE
              AND SeenAt__c = NULL AND Visible_At__c <= :cutoff
            LIMIT 2000
        ];
    }

    /** Definition + approved, complete translations for the candidate locales. */
    public static List<Notification_Translation__c> translations(Set<Id> definitionIds, Set<String> locales) {
        return [
            SELECT Definition__c, Locale__c, Title__c, Message__c, Action_Label__c
            FROM Notification_Translation__c
            WHERE Definition__c IN :definitionIds AND Locale__c IN :locales
              AND Is_Complete__c = TRUE AND Approval_Status__c = 'Approved'
        ];
    }

    public static Map<Id, Notification_Definition__c> definitions(Set<Id> ids) {
        return new Map<Id, Notification_Definition__c>([
            SELECT Id, Target_Route__c FROM Notification_Definition__c WHERE Id IN :ids
        ]);
    }

    /** Read-state writes only. Callers pass rows already filtered to the current user. */
    public static void updateRows(List<Notification_Delivery__c> rows) {
        update rows;
    }
}
