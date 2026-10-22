/**
 * Definition lifecycle rules (design section 4):
 *  - new definitions start as Draft; Active and Retired are reached only by update;
 *  - activation and retirement need the Nimbus_Notification_Activate custom permission;
 *  - one Active definition per Key (a Key may repeat on Draft and Retired records);
 *  - an Active definition is immutable (only Active to Retired is allowed); a change means a new
 *    definition record with the same Key, activated after the old one is retired;
 *  - activation requires an active Group with a matching source, an approved complete English
 *    translation for each enabled channel, valid tokens and a safe route;
 *  - activation is audited in Activated_By__c and Activated_At__c.
 * Runs without sharing: uniqueness and translation checks must see every row.
 */
public without sharing class NotificationDefinitionHandler {
    public static final String ACTIVATE_PERMISSION = 'Nimbus_Notification_Activate';
    public static final String DRAFT = 'Draft';
    public static final String ACTIVE = 'Active';
    public static final String RETIRED = 'Retired';

    private static final List<Schema.SObjectField> PROTECTED_FIELDS = new List<Schema.SObjectField>{
        Notification_Definition__c.Name, Notification_Definition__c.Key__c,
        Notification_Definition__c.Group__c, Notification_Definition__c.Mode__c,
        Notification_Definition__c.Bell_Enabled__c, Notification_Definition__c.Email_Enabled__c,
        Notification_Definition__c.Target_Route__c, Notification_Definition__c.Expiry_Days__c,
        Notification_Definition__c.Required_Tokens__c, Notification_Definition__c.Audience_Resolver_Key__c,
        Notification_Definition__c.Source_Application__c, Notification_Definition__c.Event_Type__c,
        Notification_Definition__c.Trigger_Description__c, Notification_Definition__c.Activated_By__c,
        Notification_Definition__c.Activated_At__c
    };

    public static void beforeInsert(List<Notification_Definition__c> rows) {
        for (Notification_Definition__c r : rows) {
            if (String.isNotBlank(r.Status__c) && r.Status__c != DRAFT && !NotificationGuard.isBypassed()) {
                r.addError('New definitions must be created as Draft and then activated.');
            }
        }
        validateGroups(rows);
    }

    public static void beforeUpdate(List<Notification_Definition__c> rows, Map<Id, Notification_Definition__c> oldMap) {
        List<Notification_Definition__c> activating = new List<Notification_Definition__c>();
        List<Notification_Definition__c> editable = new List<Notification_Definition__c>();
        for (Notification_Definition__c r : rows) {
            Notification_Definition__c o = oldMap.get(r.Id);
            if (o.Status__c == RETIRED) {
                if (r.Status__c != RETIRED || changed(r, o)) {
                    r.addError('A Retired definition cannot be changed. Create a new definition.');
                }
            } else if (o.Status__c == ACTIVE) {
                if (r.Status__c == ACTIVE) {
                    if (changed(r, o)) {
                        r.addError('An Active definition is immutable. Create a new definition to change it.');
                    }
                } else if (r.Status__c == RETIRED) {
                    if (!hasActivatePermission()) {
                        r.addError('Retiring a definition requires the Nimbus Notification Activate permission.');
                    } else if (changed(r, o)) {
                        r.addError('Retire a definition without changing other fields.');
                    }
                } else {
                    r.addError('An Active definition cannot return to Draft. Create a new definition.');
                }
            } else {
                editable.add(r);
                if (r.Status__c == ACTIVE) {
                    if (hasActivatePermission()) {
                        activating.add(r);
                    } else {
                        r.addError('Activating a definition requires the Nimbus Notification Activate permission.');
                    }
                }
            }
        }
        validateGroups(editable);
        if (!activating.isEmpty()) {
            validateActivation(activating);
        }
    }

    public static void beforeDelete(List<Notification_Definition__c> rows) {
        for (Notification_Definition__c r : rows) {
            if (r.Status__c != DRAFT && !NotificationGuard.isBypassed()) {
                r.addError('Only Draft definitions can be deleted. Retire an Active definition instead.');
            }
        }
    }

    private static Boolean hasActivatePermission() {
        return NotificationGuard.isBypassed() || FeatureManagement.checkPermission(ACTIVATE_PERMISSION);
    }

    private static Boolean changed(Notification_Definition__c r, Notification_Definition__c o) {
        for (Schema.SObjectField f : PROTECTED_FIELDS) {
            // Deleting the activating user clears this lookup (SetNull); that is not an edit.
            if (f == Notification_Definition__c.Activated_By__c && r.get(f) == null) {
                continue;
            }
            if (r.get(f) != o.get(f)) {
                return true;
            }
        }
        return false;
    }

    /** A definition's source must match its group's source when both are set. */
    private static void validateGroups(List<Notification_Definition__c> rows) {
        Set<Id> groupIds = new Set<Id>();
        for (Notification_Definition__c r : rows) {
            if (r.Group__c != null && String.isNotBlank(r.Source_Application__c)) {
                groupIds.add(r.Group__c);
            }
        }
        if (groupIds.isEmpty()) {
            return;
        }
        Map<Id, Notification_Group__c> groups = new Map<Id, Notification_Group__c>([
            SELECT Id, Source_Application__c FROM Notification_Group__c WHERE Id IN :groupIds
        ]);
        for (Notification_Definition__c r : rows) {
            Notification_Group__c g = groups.get(r.Group__c);
            if (g != null && String.isNotBlank(g.Source_Application__c)
                && g.Source_Application__c != r.Source_Application__c) {
                r.addError('The definition\'s Source Application must match its group\'s Source Application.');
            }
        }
    }

    private static void validateActivation(List<Notification_Definition__c> rows) {
        Set<Id> ids = new Set<Id>();
        Set<Id> groupIds = new Set<Id>();
        Map<String, Integer> keyCount = new Map<String, Integer>();
        for (Notification_Definition__c r : rows) {
            ids.add(r.Id);
            if (r.Group__c != null) {
                groupIds.add(r.Group__c);
            }
            Integer c = keyCount.get(r.Key__c);
            keyCount.put(r.Key__c, c == null ? 1 : c + 1);
        }
        Set<String> alreadyActive = new Set<String>();
        for (Notification_Definition__c d : [
            SELECT Key__c FROM Notification_Definition__c
            WHERE Key__c IN :keyCount.keySet() AND Status__c = :ACTIVE AND Id NOT IN :ids
        ]) {
            alreadyActive.add(d.Key__c);
        }
        Map<Id, Notification_Group__c> groups = new Map<Id, Notification_Group__c>([
            SELECT Id, Active__c FROM Notification_Group__c WHERE Id IN :groupIds
        ]);
        Map<Id, List<Notification_Translation__c>> translations = new Map<Id, List<Notification_Translation__c>>();
        for (Notification_Translation__c t : [
            SELECT Definition__c, Locale__c, Title__c, Message__c, Action_Label__c,
                   Email_Subject__c, Email_Body__c, Is_Complete__c, Approval_Status__c
            FROM Notification_Translation__c WHERE Definition__c IN :ids
        ]) {
            if (!translations.containsKey(t.Definition__c)) {
                translations.put(t.Definition__c, new List<Notification_Translation__c>());
            }
            translations.get(t.Definition__c).add(t);
        }
        Set<String> registry = NotificationConfig.allowedTokens();

        for (Notification_Definition__c r : rows) {
            List<String> problems = new List<String>();
            if (keyCount.get(r.Key__c) > 1 || alreadyActive.contains(r.Key__c)) {
                problems.add('Key "' + r.Key__c + '" already has an Active definition. Retire it first.');
            }
            Notification_Group__c g = groups.get(r.Group__c);
            if (g == null || g.Active__c != true) {
                problems.add('The definition needs an active group.');
            }
            if (r.Bell_Enabled__c != true && r.Email_Enabled__c != true) {
                problems.add('Enable at least one channel.');
            }
            if (String.isNotBlank(r.Target_Route__c)
                && !NotificationTargetValidator.isSafe(NotificationTokens.replaceAll(r.Target_Route__c, 'x'))) {
                problems.add('Target Route must be a same-site relative path.');
            }
            List<Notification_Translation__c> list1 = translations.get(r.Id);
            Notification_Translation__c english = findEnglish(list1);
            if (english == null) {
                problems.add('An approved, complete English (en_US or en) translation is required.');
            } else {
                if (r.Bell_Enabled__c == true && (String.isBlank(english.Title__c) || String.isBlank(english.Message__c))) {
                    problems.add('The English translation needs a title and message for the Bell channel.');
                }
                if (r.Email_Enabled__c == true && (String.isBlank(english.Email_Subject__c) || String.isBlank(english.Email_Body__c))) {
                    problems.add('The English translation needs an email subject and body for the Email channel.');
                }
            }
            Set<String> declared = NotificationTokens.parseDeclared(r.Required_Tokens__c);
            Set<String> used = NotificationTokens.extract(r.Target_Route__c);
            if (list1 != null) {
                for (Notification_Translation__c t : list1) {
                    used.addAll(NotificationTokens.extract(t.Title__c));
                    used.addAll(NotificationTokens.extract(t.Message__c));
                    used.addAll(NotificationTokens.extract(t.Action_Label__c));
                    used.addAll(NotificationTokens.extract(t.Email_Subject__c));
                    used.addAll(NotificationTokens.extract(t.Email_Body__c));
                }
            }
            List<String> undeclared = new List<String>();
            for (String tok : used) {
                if (!declared.contains(tok)) {
                    undeclared.add(tok);
                }
            }
            if (!undeclared.isEmpty()) {
                undeclared.sort();
                problems.add('Tokens used but not listed in Required Tokens: ' + String.join(undeclared, ', ') + '.');
            }
            if (!registry.isEmpty()) {
                List<String> unregistered = new List<String>();
                for (String tok : declared) {
                    if (!registry.contains(tok)) {
                        unregistered.add(tok);
                    }
                }
                if (!unregistered.isEmpty()) {
                    unregistered.sort();
                    problems.add('Tokens not in the merge token registry: ' + String.join(unregistered, ', ') + '.');
                }
            }
            if (problems.isEmpty()) {
                r.Activated_By__c = UserInfo.getUserId();
                r.Activated_At__c = Datetime.now();
            } else {
                r.addError('Cannot activate: ' + String.join(problems, ' '));
            }
        }
    }

    private static Notification_Translation__c findEnglish(List<Notification_Translation__c> list1) {
        if (list1 == null) {
            return null;
        }
        for (Notification_Translation__c t : list1) {
            if ((t.Locale__c == 'en_US' || t.Locale__c == 'en') && t.Is_Complete__c == true
                && t.Approval_Status__c == 'Approved') {
                return t;
            }
        }
        return null;
    }
}
