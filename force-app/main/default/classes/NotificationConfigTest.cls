@IsTest
private class NotificationConfigTest {
    private static Notification_Setting__mdt setting(String type, Boolean active) {
        return new Notification_Setting__mdt(Type__c = type, Active__c = active);
    }

    @IsTest
    static void normalizeLocaleAppliesAliasesAndHyphens() {
        System.assertEquals(null, NotificationConfig.normalizeLocale(' '));
        System.assertEquals('pt_BR', NotificationConfig.normalizeLocale('pt-BR'));
        Notification_Setting__mdt pt = setting('LocaleAlias', true);
        pt.Key__c = 'pt';
        pt.Value__c = 'pt_PT';
        Notification_Setting__mdt fr = setting('LocaleAlias', false);
        fr.Key__c = 'fr';
        fr.Value__c = 'fr_FR';
        NotificationConfig.settingsOverride = new List<Notification_Setting__mdt>{ pt, fr };
        System.assertEquals('pt_PT', NotificationConfig.normalizeLocale('PT'));
        System.assertEquals('fr', NotificationConfig.normalizeLocale('fr'), 'inactive alias ignored');
        System.assertEquals('pt_PT', NotificationRenderer.candidates('pt')[0]);
    }

    @IsTest
    static void tokenRegistryUsesOnlyActiveMergeTokenRows() {
        Notification_Setting__mdt on1 = setting('MergeToken', true);
        on1.Key__c = 'orderId';
        Notification_Setting__mdt off = setting('MergeToken', false);
        off.Key__c = 'old';
        Notification_Setting__mdt otherType = setting('LocaleAlias', true);
        otherType.Key__c = 'notAToken';
        NotificationConfig.settingsOverride = new List<Notification_Setting__mdt>{ on1, off, otherType };
        Set<String> t = NotificationConfig.allowedTokens();
        System.assertEquals(1, t.size());
        System.assert(t.contains('orderId'));
    }

    @IsTest
    static void killSwitchMatchesBySourceAndChannelAndIgnoresOtherTypes() {
        Notification_Setting__mdt allEmail = setting('KillSwitch', true);
        allEmail.Channel__c = 'Email';
        Notification_Setting__mdt sapBell = setting('KillSwitch', true);
        sapBell.Source_Application__c = 'SAP';
        sapBell.Channel__c = 'Bell';
        Notification_Setting__mdt inactive = setting('KillSwitch', false);
        inactive.Source_Application__c = 'WEB';
        Notification_Setting__mdt retry = setting('RetryPolicy', true); // blank source and channel, but not a kill switch
        NotificationConfig.settingsOverride = new List<Notification_Setting__mdt>{ allEmail, sapBell, inactive, retry };
        System.assert(NotificationConfig.isKilled('ANY', 'Email'));
        System.assert(NotificationConfig.isKilled('SAP', 'Bell'));
        System.assert(!NotificationConfig.isKilled('WEB', 'Bell'));
        System.assert(!NotificationConfig.isKilled('SAP', 'Other'));
    }

    @IsTest
    static void retryOffsetsParseWithDefaultFallback() {
        Notification_Setting__mdt p = setting('RetryPolicy', true);
        p.Channel__c = 'Email';
        p.Value__c = '2, 10,x,30';
        NotificationConfig.settingsOverride = new List<Notification_Setting__mdt>{ p };
        System.assertEquals(new List<Integer>{ 2, 10, 30 }, NotificationConfig.retryOffsetsMinutes('Email'));
        System.assertEquals(new List<Integer>{ 1, 5, 15, 60 }, NotificationConfig.retryOffsetsMinutes('Other'));
    }

    @IsTest
    static void tokenHelpersExtractAndParse() {
        System.assertEquals(new Set<String>{ 'a', 'b' }, NotificationTokens.extract('x {{a}} y {{ b }} {{a}}'));
        System.assertEquals(0, NotificationTokens.extract(null).size());
        System.assertEquals('/o/x', NotificationTokens.replaceAll('/o/{{id}}', 'x'));
        System.assertEquals(null, NotificationTokens.replaceAll(null, 'x'));
        System.assertEquals(new Set<String>{ 'a', 'b', 'c' }, NotificationTokens.parseDeclared('a, b;c'));
        System.assertEquals(0, NotificationTokens.parseDeclared(null).size());
    }
}
