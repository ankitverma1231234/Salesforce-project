public class ContentVersionSendToPortalHandler {
    private static BatonPortalAPI__c apiConfig;
    public static void handleAfterInsert(List<ContentVersion> newList) {
        Set<Id> contentVersionIds = new Set<Id>();
        for (ContentVersion cv : newList) {
            if (cv.Id != null) {
                contentVersionIds.add(cv.Id);
            }
        }
        if (contentVersionIds.isEmpty()) {
            return;
        }
        Set<Id> feedItemIds = getFeedItemIdsFromContentVersions(contentVersionIds);
        ensurePublicLinksExist(feedItemIds);
        for (Id cvId : contentVersionIds) {
            uploadFile(cvId);
        }
    }
    private static Set<Id> getFeedItemIdsFromContentVersions(Set<Id> contentVersionIds) {
        Set<Id> feedItemIds = new Set<Id>();
        for (FeedAttachment fa : [
            SELECT FeedEntityId
            FROM FeedAttachment
            WHERE RecordId IN :contentVersionIds
            AND Type = 'Content'
        ]) {
            if (fa.FeedEntityId != null) {
                feedItemIds.add(fa.FeedEntityId);
            }
        }
        return feedItemIds;
    }
    @future(callout=true)
    public static void uploadFile(Id contentVersionId) {
        ContentVersion cv = [
            SELECT Id, Title, FileExtension
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1];
        String endpoint = getApiEndpoint();
        if (String.isBlank(endpoint)) {
            System.debug(LoggingLevel.ERROR, 'Portal endpoint is null');
            return;
        }
        String fileUrl = URL.getOrgDomainUrl().toExternalForm()
            + '/sfc/dist/version/download/?ids=' + cv.Id;
        Map<String, Object> attachment = new Map<String, Object>{
            'url' => fileUrl,
            'filename' => cv.Title + '.' + cv.FileExtension
        };
        Map<String, Object> payload = new Map<String, Object>{
            'attachments' => new List<Object>{ attachment }
        };
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Portal upload failed. Status=' + res.getStatusCode() +
                    ', Body=' + res.getBody()
                );
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Callout exception: ' + e.getMessage()
            );
        }
    }
    public static void ensurePublicLinksExist(Set<Id> feedItemIds) {
        if (feedItemIds == null || feedItemIds.isEmpty()) {
            return;
        }
        try {
            List<FeedAttachment> feedAttachments = [
                SELECT Id, RecordId, Type, FeedEntityId
                FROM FeedAttachment
                WHERE FeedEntityId IN :feedItemIds
                AND Type = 'Content'];
            if (feedAttachments.isEmpty()) {
                return;
            }
            Set<Id> contentVersionIds = new Set<Id>();
            for (FeedAttachment fa : feedAttachments) {
                if (fa.RecordId != null) {
                    contentVersionIds.add(fa.RecordId);
                }
            }
            Map<Id, ContentDistribution> existingDistributions =
                new Map<Id, ContentDistribution>();
            for (ContentDistribution cd : [
                SELECT Id, ContentVersionId
                FROM ContentDistribution
                WHERE ContentVersionId IN :contentVersionIds
            ]) {
                existingDistributions.put(cd.ContentVersionId, cd);
            }
            List<ContentDistribution> toInsert = new List<ContentDistribution>();
            for (Id versionId : contentVersionIds) {
                if (!existingDistributions.containsKey(versionId)) {
                    ContentDistribution cd = new ContentDistribution();
                    cd.Name = 'Public Link';
                    cd.ContentVersionId = versionId;
                    cd.PreferencesAllowViewInBrowser = true;
                    cd.PreferencesAllowOriginalDownload = true;
                    cd.PreferencesLinkLatestVersion = true;
                    cd.PreferencesNotifyOnVisit = false;
                    toInsert.add(cd);
                }
            }
            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'Error ensuring public links exist: ' + ex.getMessage()
            );
        }
    }
    private static String getApiEndpoint() {
        if (apiConfig == null) {
            apiConfig = BatonPortalAPI__c.getOrgDefaults();
        }
        if (apiConfig == null || String.isBlank(apiConfig.CaseKey__c)) {
            System.debug(LoggingLevel.ERROR, 'API configuration not found');
            return null;
        }
        return apiConfig.CaseKey__c;
    }
}