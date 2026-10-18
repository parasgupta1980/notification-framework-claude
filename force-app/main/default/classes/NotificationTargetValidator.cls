/**
 * Validates notification target routes. Only same-site relative paths are allowed:
 * no javascript:, no protocol-relative URLs, no absolute URLs (open redirects).
 */
public with sharing class NotificationTargetValidator {
    public static Boolean isSafe(String route) {
        if (String.isBlank(route)) {
            return false;
        }
        String r = route.trim();
        if (!r.startsWith('/') || r.startsWith('//') || r.contains('\\') || r.contains('\n') || r.contains('\r')) {
            return false;
        }
        // A colon before the first slash-delimited segment ends would indicate a scheme; since we
        // require a leading slash, only guard encoded variants.
        String lower = r.toLowerCase();
        if (lower.contains('%2f%2f') || lower.contains('%5c') || lower.contains('javascript:')) {
            return false;
        }
        return true;
    }

    /** Returns the route if safe, otherwise null (item renders without a link). */
    public static String safeOrNull(String route) {
        return isSafe(route) ? route.trim() : null;
    }
}
