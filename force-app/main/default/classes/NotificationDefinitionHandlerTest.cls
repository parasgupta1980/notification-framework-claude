@IsTest
private class NotificationDefinitionHandlerTest {
    private static Notification_Group__c grp;

    private static void makeGroup(String source) {
        grp = new Notification_Group__c(Name = 'G', Key__c = 'g_' + String.valueOf(Crypto.getRandomInteger()).replace('-', 'n'),
            Active__c = true, Source_Application__c = source);
        insert grp;
    }

    private static Notification_Definition__c draft(String key) {
        Notification_Definition__c d = new Notification_Definition__c(
            Name = key, Key__c = key, Group__c = grp.Id, Mode__c = 'Automatic',
            Bell_Enabled__c = true, Required_Tokens__c = 'orderId', Target_Route__c = '/orders/{{orderId}}'
        );
        insert d;
        return d;
    }

    private static void translation(Id defId, String locale, String title, Boolean complete, String approval) {
        insert new Notification_Translation__c(
            Name = locale, Definition__c = defId, Locale__c = locale, Title__c = title, Message__c = 'Message',
            Action_Label__c = 'Open', Is_Complete__c = complete, Approval_Status__c = approval
        );
    }

    /**
     * Config editors need Nimbus_Notification_Config_Editor for object/field access; only activators also
     * get Nimbus_Notification_Activator (the custom permission). Assigned inside runAs to avoid mixed DML.
     */
    private static User editor(String suffix, Boolean canActivate) {
        User u = NotificationTestDataFactory.createUser(suffix);
        Set<String> names = new Set<String>{ 'Nimbus_Notification_Config_Editor' };
        if (canActivate) {
            names.add('Nimbus_Notification_Activator');
        }
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN :names]) {
            assignments.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
        }
        System.assertEquals(names.size(), assignments.size(), 'permission sets must be deployed');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert assignments;
        }
        return u;
    }

    private static User activator() {
        return editor('act', true);
    }

    private static User plainEditor(String suffix) {
        return editor(suffix, false);
    }

    private static String firstError(Database.SaveResult sr) {
        return sr.isSuccess() ? '' : sr.getErrors()[0].getMessage();
    }

    @IsTest
    static void newDefinitionsMustBeDraft() {
        makeGroup('SRC');
        Notification_Definition__c d = draft('vk');
        System.assertEquals('Draft', [SELECT Status__c FROM Notification_Definition__c WHERE Id = :d.Id].Status__c);
        Notification_Definition__c bad = new Notification_Definition__c(
            Name = 'bad', Key__c = 'bad', Group__c = grp.Id, Status__c = 'Active'
        );
        Database.SaveResult sr = Database.insert(bad, false);
        System.assert(!sr.isSuccess());
        System.assert(firstError(sr).contains('Draft'));
    }

    @IsTest
    static void activationNeedsTheCustomPermission() {
        makeGroup('SRC');
        Notification_Definition__c d = draft('perm');
        translation(d.Id, 'en_US', 'Order {{orderId}}', true, 'Approved');
        User plain = plainEditor('pln');
        System.runAs(plain) {
            d.Status__c = 'Active';
            Database.SaveResult sr = Database.update(d, false);
            System.assert(!sr.isSuccess());
            System.assert(firstError(sr).contains('permission'));
        }
    }

    @IsTest
    static void activationSucceedsAndIsAudited() {
        makeGroup('SRC');
        Notification_Definition__c d = draft('ok');
        translation(d.Id, 'en_US', 'Order {{orderId}}', true, 'Approved');
        translation(d.Id, 'de', 'Bestellung {{orderId}}', true, 'Approved');
        User act = activator();
        System.runAs(act) {
            d.Status__c = 'Active';
            Database.SaveResult sr = Database.update(d, false);
            System.assert(sr.isSuccess(), firstError(sr));
        }
        d = [SELECT Status__c, Activated_By__c, Activated_At__c FROM Notification_Definition__c WHERE Id = :d.Id];
        System.assertEquals('Active', d.Status__c);
        System.assertEquals(act.Id, d.Activated_By__c);
        System.assertNotEquals(null, d.Activated_At__c);
    }

    @IsTest
    static void activationRejectsMissingEnglishUndeclaredTokensUnsafeRouteAndInactiveGroup() {
        makeGroup('SRC');
        User act = activator();

        Notification_Definition__c noEn = draft('noen');
        translation(noEn.Id, 'de', 'Titel', true, 'Approved');
        Notification_Definition__c unapproved = draft('unappr');
        translation(unapproved.Id, 'en_US', 'T', true, 'Draft');
        Notification_Definition__c badToken = draft('badtok');
        translation(badToken.Id, 'en_US', 'Hello {{surprise}}', true, 'Approved');
        Notification_Definition__c badRoute = draft('badroute');
        badRoute.Target_Route__c = 'https://evil.example/{{orderId}}';
        update badRoute;
        translation(badRoute.Id, 'en_US', 'T', true, 'Approved');

        System.runAs(act) {
            for (Notification_Definition__c d : new List<Notification_Definition__c>{ noEn, unapproved, badToken, badRoute }) {
                d.Status__c = 'Active';
                Database.SaveResult sr = Database.update(d, false);
                System.assert(!sr.isSuccess(), d.Key__c + ' should not activate');
                System.assert(firstError(sr).startsWith('Cannot activate'), firstError(sr));
            }
        }

        grp.Active__c = false;
        update grp;
        Notification_Definition__c inactiveGroup = draft('nogrp');
        translation(inactiveGroup.Id, 'en_US', 'T', true, 'Approved');
        System.runAs(act) {
            inactiveGroup.Status__c = 'Active';
            System.assert(firstError(Database.update(inactiveGroup, false)).contains('active group'));
        }
    }

    @IsTest
    static void emailChannelNeedsSubjectAndBodyAndRegistryIsEnforced() {
        makeGroup('SRC');
        User act = activator();
        Notification_Definition__c d = draft('mail');
        d.Bell_Enabled__c = false;
        d.Email_Enabled__c = true;
        update d;
        translation(d.Id, 'en_US', 'T', true, 'Approved');
        System.runAs(act) {
            d.Status__c = 'Active';
            System.assert(firstError(Database.update(d, false)).contains('email subject and body'));
        }

        Notification_Definition__c none = draft('nochan');
        none.Bell_Enabled__c = false;
        update none;
        System.runAs(act) {
            none.Status__c = 'Active';
            System.assert(firstError(Database.update(none, false)).contains('at least one channel'));
        }

        NotificationConfig.settingsOverride = new List<Notification_Setting__mdt>{
            new Notification_Setting__mdt(Type__c = 'MergeToken', Key__c = 'somethingElse', Active__c = true)
        };
        Notification_Definition__c reg = draft('reg');
        translation(reg.Id, 'en_US', 'Order {{orderId}}', true, 'Approved');
        System.runAs(act) {
            reg.Status__c = 'Active';
            System.assert(firstError(Database.update(reg, false)).contains('registry'));
        }
    }

    @IsTest
    static void onlyOneActiveDefinitionPerKey() {
        makeGroup('SRC');
        User act = activator();
        // a Key may repeat on records: the replacement is a new definition with the same Key
        Notification_Definition__c first = draft('one');
        Notification_Definition__c second = draft('one');
        translation(first.Id, 'en_US', 'Order {{orderId}}', true, 'Approved');
        translation(second.Id, 'en_US', 'Order {{orderId}}', true, 'Approved');
        System.runAs(act) {
            first.Status__c = 'Active';
            System.assert(Database.update(first, false).isSuccess());
            second.Status__c = 'Active';
            System.assert(firstError(Database.update(second, false)).contains('already has an Active definition'));
            // retiring the first frees the key
            first = [SELECT Id, Status__c FROM Notification_Definition__c WHERE Id = :first.Id];
            first.Status__c = 'Retired';
            System.assert(Database.update(first, false).isSuccess());
            System.assert(Database.update(second, false).isSuccess());
        }
    }

    @IsTest
    static void twoDefinitionsOfTheSameKeyInOneBatchCannotBothActivate() {
        makeGroup('SRC');
        User act = activator();
        Notification_Definition__c a = draft('batch');
        Notification_Definition__c b = draft('batch');
        translation(a.Id, 'en_US', 'Order {{orderId}}', true, 'Approved');
        translation(b.Id, 'en_US', 'Order {{orderId}}', true, 'Approved');
        System.runAs(act) {
            a.Status__c = 'Active';
            b.Status__c = 'Active';
            List<Database.SaveResult> res = Database.update(new List<Notification_Definition__c>{ a, b }, false);
            System.assert(!res[0].isSuccess() && !res[1].isSuccess());
        }
    }

    @IsTest
    static void activeDefinitionsAreImmutableRetireNeedsPermissionAndRetiredIsTerminal() {
        makeGroup('SRC');
        Notification_Definition__c d = NotificationTestDataFactory.createDefinition('frozen', '/x'); // seeded Active
        User plain = plainEditor('frz');
        User act = activator();

        System.runAs(act) {
            d.Target_Route__c = '/changed';
            System.assert(firstError(Database.update(d, false)).contains('immutable'));
            d = [SELECT Status__c, Target_Route__c FROM Notification_Definition__c WHERE Id = :d.Id];
            d.Status__c = 'Draft';
            System.assert(firstError(Database.update(d, false)).contains('cannot return to Draft'));
        }
        System.runAs(plain) {
            d = [SELECT Status__c FROM Notification_Definition__c WHERE Id = :d.Id];
            d.Status__c = 'Retired';
            System.assert(firstError(Database.update(d, false)).contains('permission'));
        }
        System.runAs(act) {
            d = [SELECT Status__c, Target_Route__c FROM Notification_Definition__c WHERE Id = :d.Id];
            d.Status__c = 'Retired';
            d.Target_Route__c = '/sneaky';
            System.assert(firstError(Database.update(d, false)).contains('without changing'));
            d = [SELECT Status__c FROM Notification_Definition__c WHERE Id = :d.Id];
            d.Status__c = 'Retired';
            System.assert(Database.update(d, false).isSuccess());
            d = [SELECT Status__c, Name FROM Notification_Definition__c WHERE Id = :d.Id];
            d.Status__c = 'Active';
            System.assert(firstError(Database.update(d, false)).contains('Retired'));
        }
    }

    @IsTest
    static void onlyDraftDefinitionsCanBeDeleted() {
        makeGroup('SRC');
        Notification_Definition__c active = NotificationTestDataFactory.createDefinition('del_a', '/x');
        System.assert(!Database.delete(active, false).isSuccess());
        Notification_Definition__c d = draft('del_d');
        System.assert(Database.delete(d, false).isSuccess());
    }

    @IsTest
    static void definitionAndGroupSourceMustMatch() {
        makeGroup('SRC_A');
        Notification_Definition__c bad = new Notification_Definition__c(
            Name = 'src', Key__c = 'src', Group__c = grp.Id, Source_Application__c = 'SRC_B'
        );
        System.assert(firstError(Database.insert(bad, false)).contains('Source Application'));
        Notification_Definition__c ok = new Notification_Definition__c(
            Name = 'src2', Key__c = 'src2', Group__c = grp.Id, Source_Application__c = 'SRC_A'
        );
        System.assert(Database.insert(ok, false).isSuccess());
    }

    @IsTest
    static void translationsAreNormalizedKeyedAndFrozenWithTheirDefinition() {
        makeGroup('SRC');
        Notification_Definition__c d = draft('tr');
        translation(d.Id, 'pt-BR', 'Titulo', false, 'Draft');
        Notification_Translation__c t = [SELECT Locale__c, DefinitionLocaleKey__c FROM Notification_Translation__c WHERE Definition__c = :d.Id];
        System.assertEquals('pt_BR', t.Locale__c);
        System.assertEquals(NotificationKeys.definitionLocaleKey(d.Id, 'pt_BR'), t.DefinitionLocaleKey__c);

        Notification_Translation__c dup = new Notification_Translation__c(Name = 'x', Definition__c = d.Id, Locale__c = 'pt_BR', Title__c = 'T', Message__c = 'M');
        System.assert(!Database.insert(dup, false).isSuccess(), 'one translation per definition and locale');

        Notification_Definition__c frozen = NotificationTestDataFactory.createDefinition('tr_frozen', '/x');
        NotificationTestDataFactory.addTranslation(frozen.Id, 'en_US', 'T', 'M');
        Notification_Translation__c ft = [SELECT Id, Title__c FROM Notification_Translation__c WHERE Definition__c = :frozen.Id];
        ft.Title__c = 'changed';
        System.assert(!Database.update(ft, false).isSuccess());
        System.assert(!Database.delete(ft, false).isSuccess());
        Notification_Translation__c added = new Notification_Translation__c(Name = 'fr', Definition__c = frozen.Id, Locale__c = 'fr', Title__c = 'T', Message__c = 'M');
        System.assert(!Database.insert(added, false).isSuccess());

        System.assert(Database.delete(t, false).isSuccess(), 'draft translations can be deleted');
    }
}
