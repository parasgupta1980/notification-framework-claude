@IsTest
public class NotificationTestDataFactory {
    public static User createUser(String suffix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String u = 'nimbus' + suffix + System.currentTimeMillis() + '@example.com';
        User usr = new User(
            Alias = 'nb' + suffix.left(5), Email = u, Username = u, LastName = 'Notif' + suffix,
            ProfileId = p.Id, TimeZoneSidKey = 'GMT', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        satisfyOrgUserRules(usr);
        insert usr;
        return usr;
    }

    /**
     * Some orgs enforce validation rules on internal Users (e.g. Business_Segment_PC3__c).
     * Populated dynamically so this class compiles in orgs where the field does not exist.
     */
    private static void satisfyOrgUserRules(User usr) {
        Schema.SObjectField f = Schema.SObjectType.User.fields.getMap().get('Business_Segment_PC3__c');
        if (f == null) {
            return;
        }
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.getType() == Schema.DisplayType.PICKLIST || d.getType() == Schema.DisplayType.MULTIPICKLIST) {
            for (Schema.PicklistEntry e : d.getPicklistValues()) {
                if (e.isActive()) {
                    usr.put(f, e.getValue());
                    return;
                }
            }
        } else if (d.getType() == Schema.DisplayType.STRING) {
            usr.put(f, 'TEST'.left(d.getLength()));
        }
    }

    public static Notification_Definition__c createDefinition(String key, String route) {
        Notification_Group__c g = new Notification_Group__c(Name = 'Group ' + key, Key__c = 'g_' + key);
        insert g;
        Notification_Definition__c d = new Notification_Definition__c(
            Name = key, Key__c = key, Group__c = g.Id,
            Status__c = 'Active', Target_Route__c = route
        );
        Boolean previous = NotificationGuard.bypass;
        NotificationGuard.bypass = true; // fixture is seeded already Active
        insert d;
        NotificationGuard.bypass = previous;
        return d;
    }

    public static void addTranslation(Id definitionId, String locale, String title, String message) {
        Boolean previous = NotificationGuard.bypass;
        NotificationGuard.bypass = true; // the fixture definition is already Active
        insert new Notification_Translation__c(
            Name = locale, Definition__c = definitionId, Locale__c = locale,
            Title__c = title, Message__c = message, Action_Label__c = 'Open',
            Is_Complete__c = true, Approval_Status__c = 'Approved'
        );
        NotificationGuard.bypass = previous;
    }

    public static Notification_Request__c createRequest(Id definitionId, String eventId, String contextJson) {
        Notification_Request__c r = new Notification_Request__c(
            Source_Application__c = 'TEST', Business_Event_Id__c = eventId, EventKey__c = 'ek_' + eventId,
            Definition__c = definitionId, Context_Json__c = contextJson, Status__c = 'Dispatching'
        );
        insert r;
        return r;
    }

    public static Notification_Delivery__c createBell(Id requestId, Id userId, String key, String storeKey, Datetime visibleAt) {
        Notification_Delivery__c d = new Notification_Delivery__c(
            Request__c = requestId, Recipient_User__c = userId, Channel__c = 'Bell',
            DeliveryKey__c = key, Status__c = 'Visible', Store_Key__c = storeKey, Visible_At__c = visibleAt
        );
        insert d;
        return d;
    }
}
