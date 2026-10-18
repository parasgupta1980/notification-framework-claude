/** Data transfer objects returned to the bell LWCs. No SObjects leave Apex. */
public with sharing class NotificationInboxDto {
    public class Summary {
        @AuraEnabled public Integer unreadCount;
        @AuraEnabled public Boolean unreadCountCapped;
        @AuraEnabled public Integer unseenCount;
        @AuraEnabled public Datetime latestVisibleAt;
    }

    public class Item {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String actionLabel;
        @AuraEnabled public String targetUrl;
        @AuraEnabled public Datetime visibleAt;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public Boolean unavailable;
        @AuraEnabled public String renderedLocale;
    }

    public class Page {
        @AuraEnabled public List<Item> items = new List<Item>();
        @AuraEnabled public String nextCursor;
        @AuraEnabled public Boolean hasMore = false;
    }
}
