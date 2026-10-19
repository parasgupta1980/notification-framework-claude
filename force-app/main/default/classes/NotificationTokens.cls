/** {{token}} helpers shared by activation validation and (later) the ingress. */
public with sharing class NotificationTokens {
    private static final Pattern TOKEN = Pattern.compile('\\{\\{\\s*([A-Za-z0-9_]+)\\s*\\}\\}');

    /** Token names used in a template. */
    public static Set<String> extract(String template) {
        Set<String> found = new Set<String>();
        if (String.isBlank(template)) {
            return found;
        }
        Matcher m = TOKEN.matcher(template);
        while (m.find()) {
            found.add(m.group(1));
        }
        return found;
    }

    /** Replaces every token with a placeholder (used to validate routes that contain tokens). */
    public static String replaceAll(String template, String replacement) {
        if (String.isBlank(template)) {
            return template;
        }
        return TOKEN.matcher(template).replaceAll(replacement);
    }

    /** Parses the Required_Tokens__c list (comma, semicolon or whitespace separated). */
    public static Set<String> parseDeclared(String csv) {
        Set<String> out = new Set<String>();
        if (String.isBlank(csv)) {
            return out;
        }
        for (String s : csv.trim().split('[,;\\s]+')) {
            if (String.isNotBlank(s)) {
                out.add(s.trim());
            }
        }
        return out;
    }
}
