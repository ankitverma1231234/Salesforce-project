public class GeminiCacheManager {

    // The Platform Cache partition `GeminiCache` is intentionally optional. When
    // the partition is not provisioned in the org (or is full), every put/get is
    // a true no-op — there is NO in-memory fallback. The previous in-memory Map
    // gave a false sense of caching: it lived in the current Apex transaction's
    // heap only, so any cross-transaction reader (notably the VF page rendered
    // by Page.getContentAsPDF()) always missed. Removing the fallback prevents
    // that whole class of intermittent bug. Callers that truly need cross-context
    // handoff must use a persisted store (e.g. an Attachment), not this cache.

    public static void putSummary(Id contentDocumentId, String summary) {
        putValue(buildKey('SUM', contentDocumentId), summary);
    }

    public static String getSummary(Id contentDocumentId) {
        return getValue(buildKey('SUM', contentDocumentId));
    }

    public static void removeSummary(Id contentDocumentId) {
        removeValue(buildKey('SUM', contentDocumentId));
    }

    public static void putAnalysis(Id contentDocumentId, String analysisJson) {
        putValue(buildKey('ANL', contentDocumentId), analysisJson);
    }

    public static String getAnalysis(Id contentDocumentId) {
        return getValue(buildKey('ANL', contentDocumentId));
    }

    public static void removeAnalysis(Id contentDocumentId) {
        removeValue(buildKey('ANL', contentDocumentId));
    }

    private static void putValue(String key, String value) {
        try {
            Cache.Org.put('local.GeminiCache.' + key, value, 7200);
        } catch (Exception e) {
            System.debug(LoggingLevel.DEBUG, 'Platform Cache put no-op (partition unavailable): ' + e.getMessage());
        }
    }

    private static String getValue(String key) {
        try {
            return (String) Cache.Org.get('local.GeminiCache.' + key);
        } catch (Exception e) {
            System.debug(LoggingLevel.DEBUG, 'Platform Cache get no-op (partition unavailable): ' + e.getMessage());
            return null;
        }
    }

    private static void removeValue(String key) {
        try {
            Cache.Org.remove('local.GeminiCache.' + key);
        } catch (Exception e) {
            System.debug(LoggingLevel.DEBUG, 'Platform Cache remove no-op (partition unavailable): ' + e.getMessage());
        }
    }

    private static String buildKey(String prefix, Id contentDocumentId) {
        return prefix + String.valueOf(contentDocumentId).left(15);
    }
}