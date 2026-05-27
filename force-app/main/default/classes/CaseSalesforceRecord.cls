public class CaseSalesforceRecord {
    private static Set<Id> processedCaseIds = new Set<Id>();
    private static Set<Id> processedFeedItemIds = new Set<Id>();
    private static Set<Id> descriptionFeedItemIds = new Set<Id>();
    private static Set<Id> casesWithDescriptionProcessed = new Set<Id>();
    private static BatonPortalAPI__c apiConfig;
    
    public static void sendCaseDataToThirdParty(Set<Id> caseIds, String operation) {
        if (caseIds == null || caseIds.isEmpty()) {
            return;
        }
        
        Set<Id> newCaseIds = new Set<Id>();
        for (Id caseId : caseIds) {
            if (!processedCaseIds.contains(caseId)) {
                newCaseIds.add(caseId);
                processedCaseIds.add(caseId);
            }
        }
        
        if (!newCaseIds.isEmpty()) {
            sendToThirdPartyFuture(newCaseIds, operation, false);
        }
    }
    
    public static void sendCaseDataToThirdParty(Set<Id> caseIds, String operation, Set<Id> contentDocumentIds) {
        sendCaseDataToThirdParty(caseIds, operation);
    }
    
    public static void sendChatterDataToThirdParty(Id feedItemId, String operation) {
        if (feedItemId == null || processedFeedItemIds.contains(feedItemId)) {
            return;
        }
        
        if (descriptionFeedItemIds.contains(feedItemId)) {
            return;
        }
        processedFeedItemIds.add(feedItemId);
        sendChatterToThirdPartyFuture(feedItemId, operation);
    }
    
    public static Boolean isDescriptionFeedItem(Id feedItemId) {
        return descriptionFeedItemIds.contains(feedItemId);
    }
    
    public static Boolean isCaseDescriptionJustProcessed(Id caseId) {
        return casesWithDescriptionProcessed.contains(caseId);
    }
    
    public static void handleCaseDescriptions(Map<Id, String> caseDescriptionMap) {
        if (caseDescriptionMap == null || caseDescriptionMap.isEmpty()) {
            return;
        }
        casesWithDescriptionProcessed.addAll(caseDescriptionMap.keySet());
        
        List<FeedItem> feedItemsToInsert = new List<FeedItem>();
        for (Id caseId : caseDescriptionMap.keySet()) {
            String description = caseDescriptionMap.get(caseId);
            if (String.isNotBlank(description)) {
                FeedItem feedItem = new FeedItem();
                feedItem.ParentId = caseId;
                feedItem.Body = description;
                feedItem.Type = 'TextPost';
                feedItemsToInsert.add(feedItem);
            }
        }
        
        if (!feedItemsToInsert.isEmpty()) {
            try {
                insert feedItemsToInsert;
                for (FeedItem fi : feedItemsToInsert) {
                    descriptionFeedItemIds.add(fi.Id);
                    processedFeedItemIds.add(fi.Id);
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Error creating FeedItems: ' + ex.getMessage());
            }
        }
        
        Map<String, String> stringMap = new Map<String, String>();
        for (Id caseId : caseDescriptionMap.keySet()) {
            stringMap.put(String.valueOf(caseId), caseDescriptionMap.get(caseId));
        }
        
        String caseDescriptionJson = JSON.serialize(stringMap);
        sendDescriptionsAsChatterFuture(caseDescriptionJson);
    }
    
    public static void handleCaseDescription(Id caseId, String description) {
        if (caseId != null && String.isNotBlank(description)) {
            handleCaseDescriptions(new Map<Id, String>{caseId => description});
        }
    }
    
    @future(callout=true)
    public static void sendDescriptionsAsChatterFuture(String caseDescriptionJson) {
        try {
            String endpoint = getApiEndpoint();
            if (String.isBlank(endpoint)) {
                return;
            }
            
            Map<String, String> caseDescriptionMap = (Map<String, String>) JSON.deserialize(
                caseDescriptionJson,
                Map<String, String>.class
            );
            
            if (caseDescriptionMap == null || caseDescriptionMap.isEmpty()) {
                return;
            }
            
            Set<Id> caseIds = new Set<Id>();
            for (String caseIdStr : caseDescriptionMap.keySet()) {
                caseIds.add((Id) caseIdStr);
            }
            
            Map<Id, Case> caseMap = new Map<Id, Case>([
                SELECT Id, AccountId, ContactId, Account.Name, Account.IsPersonAccount
                FROM Case
                WHERE Id IN :caseIds
                AND AccountId != null
                AND Account.IsPersonAccount = true
            ]);
            
            if (caseMap.isEmpty()) {
                System.debug('No valid cases found');
                return;
            }
            
            List<Map<String, Object>> allConversations = new List<Map<String, Object>>();
            
            for (String caseIdStr : caseDescriptionMap.keySet()) {
                Id caseId = (Id) caseIdStr;
                Case caseRecord = caseMap.get(caseId);
                if (caseRecord == null) {
                    continue;
                }
                
                String description = caseDescriptionMap.get(caseIdStr);
                if (String.isBlank(description)) {
                    continue;
                }
                
                Map<String, Object> chatterMessage = new Map<String, Object>{
                    'case_message_id' => String.valueOf(caseId),
                        'account_id' => String.valueOf(caseRecord.AccountId),
                        'contact_id' => caseRecord.ContactId != null ? String.valueOf(caseRecord.ContactId) : '',
                            'sender_id' => UserInfo.getUserId(),
                            'sender_name' => UserInfo.getName(),
                            'sender_type' => 'member',
                            'message_body' => description,
                            'is_read' => false
                            };
                                
                                allConversations.add(chatterMessage);
            }
            
            if (!allConversations.isEmpty()) {
                Map<String, Object> payload = new Map<String, Object>{
                    'conversations' => allConversations
                        };
                            
                            HttpResponse response = sendHttpRequest(endpoint, payload);
                logResponse('Description Chatter', response);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error in sendDescriptionsAsChatterFuture: ' + ex.getMessage());
        }
    }
    
    @future(callout=true)
    public static void sendToThirdPartyFuture(
        Set<Id> caseIds,
        String operation,
        Boolean includeAttachments
    ) {
        try {
            String endpoint = getApiEndpoint();
            if (String.isBlank(endpoint)) {
                return;
            }
            
            Map<Id, List<Map<String, Object>>> caseToAttachmentsMap = new Map<Id, List<Map<String, Object>>>();
            
            if (includeAttachments) {
                
                List<ContentDocumentLink> cdLinks = [
                    SELECT ContentDocumentId, LinkedEntityId
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId IN :caseIds
                ];
                
                Set<Id> contentDocumentIds = new Set<Id>();
                for (ContentDocumentLink cdl : cdLinks) {
                    contentDocumentIds.add(cdl.ContentDocumentId);
                }
                
                Map<Id, ContentVersion> contentVersionMap = new Map<Id, ContentVersion>();
                
                if (!contentDocumentIds.isEmpty()) {
                    for (ContentVersion cv : [
                        SELECT Id, ContentDocumentId, Title, FileExtension
                        FROM ContentVersion
                        WHERE ContentDocumentId IN :contentDocumentIds
                        AND IsLatest = true
                    ]) {
                        contentVersionMap.put(cv.ContentDocumentId, cv);
                    }
                }
                
                Map<Id, String> versionIdToUrlMap = new Map<Id, String>();
                
                Set<Id> versionIds = new Set<Id>();
                for (ContentVersion cv : contentVersionMap.values()) {
                    versionIds.add(cv.Id);
                }
                
                for (ContentDistribution cd : [
                    SELECT ContentVersionId, DistributionPublicUrl
                    FROM ContentDistribution
                    WHERE ContentVersionId IN :versionIds
                ]) {
                    versionIdToUrlMap.put(cd.ContentVersionId, cd.DistributionPublicUrl);
                }
                
                for (ContentDocumentLink cdl : cdLinks) {
                    
                    Id caseId = cdl.LinkedEntityId;
                    ContentVersion cv = contentVersionMap.get(cdl.ContentDocumentId);
                    
                    if (cv == null) continue;
                    
                    String publicUrl = versionIdToUrlMap.get(cv.Id);
                    if (String.isBlank(publicUrl)) continue;
                    
                    if (!caseToAttachmentsMap.containsKey(caseId)) {
                        caseToAttachmentsMap.put(caseId, new List<Map<String, Object>>());
                    }
                    
                    caseToAttachmentsMap.get(caseId).add(new Map<String, Object>{
                        'url' => publicUrl,
                            'filename' => cv.Title + '.' + cv.FileExtension
                            });
                }
            } else {
                System.debug('Skipping attachment queries - includeAttachments is false');
            }
            
            List<Map<String, Object>> allMessages = new List<Map<String, Object>>();
            
            for (Id caseId : caseIds) {
                Map<String, Object> caseData = buildCasePayload(caseId);
                if (caseData == null || caseData.isEmpty()) continue;
                
                caseData.put('operation', operation);
                
                if (includeAttachments && caseToAttachmentsMap.containsKey(caseId)) {
                    List<Map<String, Object>> attachments = caseToAttachmentsMap.get(caseId);
                    if (attachments != null && !attachments.isEmpty()) {
                        caseData.put('attachments', attachments);
                    }
                }
                
                allMessages.add(caseData);
            }
            
            if (!allMessages.isEmpty()) {
                Map<String, Object> payload = new Map<String, Object>{
                    'messages' => allMessages
                        };
                            
                            HttpResponse response = sendHttpRequest(endpoint, payload);
                logResponse('Case Data', response);
            }
            
        } catch (Exception ex) {
            System.debug('Error in sendToThirdPartyFuture: ' + ex.getMessage());
        }
    }
    public static void createPublicLinksSync(Set<Id> caseIds) {
        
        List<ContentDocumentLink> cdLinks = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :caseIds
        ];
        
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink cdl : cdLinks) {
            documentIds.add(cdl.ContentDocumentId);
        }
        
        if (!documentIds.isEmpty()) {
            ensurePublicLinksForDocuments(documentIds);
        }
    }
    
    @future(callout=true)
    public static void sendChatterToThirdPartyFuture(Id feedItemId, String operation) {
        try {
            String endpoint = getApiEndpoint();
            if (String.isBlank(endpoint)) {
                return;
            }
            
            Map<String, Object> chatterData = buildChatterPayload(feedItemId);
            if (chatterData != null && !chatterData.isEmpty()) {
                HttpResponse response = sendHttpRequest(endpoint, chatterData);
                logResponse('Chatter Data', response);
            }
        } catch (Exception ex) {
            System.debug('Error in sendChatterToThirdPartyFuture: ' + ex.getMessage());
        }
    }
    
    private static Map<Id, String> createOrFetchPublicLinks(List<ContentVersion> contentVersions) {
        Map<Id, String> versionIdToUrlMap = new Map<Id, String>();
        
        if (contentVersions == null || contentVersions.isEmpty()) {
            return versionIdToUrlMap;
        }
        
        try {
            Set<Id> versionIds = new Set<Id>();
            for (ContentVersion cv : contentVersions) {
                versionIds.add(cv.Id);
            }
            
            // Check existing distributions first
            Map<Id, ContentDistribution> existingDistributions = new Map<Id, ContentDistribution>();
            for (ContentDistribution cd : [
                SELECT Id, ContentVersionId, DistributionPublicUrl
                FROM ContentDistribution
                WHERE ContentVersionId IN :versionIds
            ]) {
                existingDistributions.put(cd.ContentVersionId, cd);
                versionIdToUrlMap.put(cd.ContentVersionId, cd.DistributionPublicUrl);
            }
            
            // Create distributions for versions that don't have one yet
            List<ContentDistribution> toInsert = new List<ContentDistribution>();
            for (ContentVersion cv : contentVersions) {
                if (!existingDistributions.containsKey(cv.Id)) {
                    ContentDistribution cd = new ContentDistribution();
                    cd.Name = 'Public Link - ' + cv.Title;
                    cd.ContentVersionId = cv.Id;
                    cd.PreferencesAllowViewInBrowser = true;
                    cd.PreferencesAllowOriginalDownload = true;
                    cd.PreferencesLinkLatestVersion = true;
                    cd.PreferencesNotifyOnVisit = false;
                    toInsert.add(cd);
                }
            }
            
            if (!toInsert.isEmpty()) {
                insert toInsert;
                
                for (ContentDistribution cd : [
                    SELECT Id, ContentVersionId, DistributionPublicUrl
                    FROM ContentDistribution
                    WHERE Id IN :toInsert
                ]) {
                    versionIdToUrlMap.put(cd.ContentVersionId, cd.DistributionPublicUrl);
                }
            }
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error creating public links: ' + ex.getMessage());
        }
        
        return versionIdToUrlMap;
    }
    
    public static Map<String, Object> buildCasePayload(Id caseId) {
        Map<String, Object> payload = new Map<String, Object>();
        
        try {
            List<Case> cases = [
                SELECT Id, CaseNumber, Subject, Description, Status, Reason, Account.Name,
                Priority, Origin, Type, SuppliedPhone, SuppliedEmail, ContactId,
                OwnerId, AccountId, IsClosed, CreatedDate, CreatedById,
                LastModifiedDate, LastModifiedById, ClosedDate, Account.IsPersonAccount
                FROM Case
                WHERE Id = :caseId
                AND AccountId != null
                AND Account.IsPersonAccount = true
                LIMIT 1
            ];
            
            if (cases.isEmpty()) {
                return payload;
            }
            
            Case c = cases[0];
            payload.put('Id', String.valueOf(c.Id));
            payload.put('CaseNumber', c.CaseNumber != null ? c.CaseNumber : '');
            payload.put('Subject', c.Subject != null ? c.Subject : '');
            payload.put('Description', c.Description != null ? c.Description : '');
            payload.put('Status', c.Status != null ? c.Status : '');
            payload.put('Reason', c.Reason != null ? c.Reason : '');
            payload.put('Priority', c.Priority != null ? c.Priority : '');
            payload.put('Origin', c.Origin != null ? c.Origin : '');
            payload.put('Type', c.Type != null ? c.Type : '');
            payload.put('SuppliedPhone', c.SuppliedPhone != null ? c.SuppliedPhone : '');
            payload.put('SuppliedEmail', c.SuppliedEmail != null ? c.SuppliedEmail : '');
            payload.put('ContactId', c.ContactId != null ? String.valueOf(c.ContactId) : '');
            payload.put('OwnerId', c.OwnerId != null ? String.valueOf(c.OwnerId) : '');
            payload.put('AccountId', c.AccountId != null ? String.valueOf(c.AccountId) : '');
            payload.put('CreatedDate', c.CreatedDate != null ? formatDateTime(c.CreatedDate) : null);
            payload.put('CreatedById', c.CreatedById != null ? String.valueOf(c.CreatedById) : '');
            payload.put('LastModifiedDate', c.LastModifiedDate != null ? formatDateTime(c.LastModifiedDate) : null);
            payload.put('ClosedDate', c.ClosedDate != null ? formatDateTime(c.ClosedDate) : null);
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error building case payload: ' + ex.getMessage());
        }
        
        return payload;
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
                AND Type = 'Content'
            ];
            
            if (feedAttachments.isEmpty()) {
                return;
            }
            
            Set<Id> contentVersionIds = new Set<Id>();
            for (FeedAttachment fa : feedAttachments) {
                contentVersionIds.add(fa.RecordId);
            }
            
            Map<Id, ContentDistribution> existingDistributions = new Map<Id, ContentDistribution>();
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
            System.debug(LoggingLevel.ERROR, 'Error ensuring public links exist: ' + ex.getMessage());
        }
    }
    
    public static void ensurePublicLinksForDocuments(Set<Id> documentIds) {
        if (documentIds == null || documentIds.isEmpty()) {
            return;
        }
        
        try {
            List<ContentVersion> versions = [
                SELECT Id, ContentDocumentId, Title, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId IN :documentIds
                AND IsLatest = true
            ];
            
            if (versions.isEmpty()) {
                return;
            }
            
            Set<Id> versionIds = new Set<Id>();
            for (ContentVersion cv : versions) {
                versionIds.add(cv.Id);
            }
            
            Map<Id, ContentDistribution> existingDistributions = new Map<Id, ContentDistribution>();
            for (ContentDistribution cd : [
                SELECT Id, ContentVersionId
                FROM ContentDistribution
                WHERE ContentVersionId IN :versionIds
            ]) {
                existingDistributions.put(cd.ContentVersionId, cd);
            }
            
            List<ContentDistribution> toInsert = new List<ContentDistribution>();
            for (ContentVersion cv : versions) {
                if (!existingDistributions.containsKey(cv.Id)) {
                    ContentDistribution cd = new ContentDistribution();
                    cd.Name = 'Public Link - ' + cv.Title;
                    cd.ContentVersionId = cv.Id;
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
            System.debug(LoggingLevel.ERROR, 'Error creating public links for documents: ' + ex.getMessage());
        }
    }
    
    public static Map<String, Object> buildChatterPayload(Id feedItemId) {
        Map<String, Object> payload = new Map<String, Object>();
        
        try {
            List<FeedItem> feedItems = [
                SELECT Id, ParentId, Body
                FROM FeedItem
                WHERE Id = :feedItemId
                AND Parent.Type = 'Case'
                LIMIT 1
            ];
            
            if (feedItems.isEmpty()) {
                return payload;
            }
            
            FeedItem feed = feedItems[0];
            Id caseId = feed.ParentId;
            
            String accountId = '';
            String contactId = '';
            String accountName = '';
            
            if (caseId != null) {
                Case cs = [
                    SELECT AccountId, ContactId, Account.Name
                    FROM Case
                    WHERE Id = :caseId
                    LIMIT 1
                ];
                
                accountName = cs.Account != null ? cs.Account.Name : '';
                accountId = cs.AccountId != null ? String.valueOf(cs.AccountId) : '';
                contactId = cs.ContactId != null ? String.valueOf(cs.ContactId) : '';
            }
            
            Map<String, Object> chatterMessage = new Map<String, Object>();
            chatterMessage.put('case_message_id', caseId != null ? String.valueOf(caseId) : '');
            chatterMessage.put('account_id', accountId);
            chatterMessage.put('contact_id', contactId);
            chatterMessage.put('sender_id', UserInfo.getUserId());
            chatterMessage.put('sender_name', UserInfo.getName());
            chatterMessage.put('sender_type', 'member');
            chatterMessage.put('message_body', feed.Body != null ? feed.Body : '');
            chatterMessage.put('is_read', false);
            
            List<FeedAttachment> feedAttachments = [
                SELECT Id, RecordId, Type
                FROM FeedAttachment
                WHERE FeedEntityId = :feed.Id
                AND Type = 'Content'
            ];
            
            Set<Id> contentVersionIds = new Set<Id>();
            for (FeedAttachment fa : feedAttachments) {
                contentVersionIds.add(fa.RecordId);
            }
            
            List<Map<String, Object>> attachmentsList = new List<Map<String, Object>>();
            
            if (!contentVersionIds.isEmpty()) {
                Map<Id, String> versionIdToUrl = new Map<Id, String>();
                
                for (ContentDistribution cd : [
                    SELECT ContentVersionId, DistributionPublicUrl
                    FROM ContentDistribution
                    WHERE ContentVersionId IN :contentVersionIds
                ]) {
                    versionIdToUrl.put(cd.ContentVersionId, cd.DistributionPublicUrl);
                }
                
                List<ContentVersion> versions = [
                    SELECT Id, Title, FileExtension
                    FROM ContentVersion
                    WHERE Id IN :contentVersionIds
                ];
                
                for (ContentVersion cv : versions) {
                    String fileUrl = versionIdToUrl.get(cv.Id);
                    if (String.isNotBlank(fileUrl)) {
                        Map<String, Object> fileMap = new Map<String, Object>();
                        fileMap.put('filename', cv.Title + '.' + cv.FileExtension);
                        fileMap.put('url', fileUrl);
                        attachmentsList.add(fileMap);
                    }
                }
            }
            
            if (!attachmentsList.isEmpty()) {
                chatterMessage.put('attachments', attachmentsList);
            }
            
            List<Map<String, Object>> conversation = new List<Map<String, Object>>();
            conversation.add(chatterMessage);
            payload.put('conversations', conversation);
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error building chatter payload: ' + ex.getMessage());
        }
        
        return payload;
    }
    
    private static String getApiEndpoint() {
        if (apiConfig == null) {
            apiConfig = BatonPortalAPI__c.getOrgDefaults();
        }
        
        if (apiConfig == null || String.isBlank(apiConfig.CaseKey__c)) {
            return null;
        }
        
        return apiConfig.CaseKey__c;
    }
    
    private static HttpResponse sendHttpRequest(String endpoint, Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(payload));
        
        System.debug('Payload:\n' + JSON.serializePretty(payload));
        
        return new Http().send(req);
    }
    
    private static void logResponse(String context, HttpResponse response) {
        if (response != null) {
            System.debug(context + ' Response Code: ' + response.getStatusCode());
            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                System.debug('Successfully sent ' + context);
            } else {
                System.debug(LoggingLevel.ERROR, 'Failed to send ' + context + '. Status: ' + response.getStatusCode());
            }
        }
    }
    
    private static String formatDateTime(Datetime dt) {
        return dt != null ? dt.format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') : null;
    }
    
    @TestVisible
    private static void resetProcessedCases() {
        processedCaseIds.clear();
    }
    
    @TestVisible
    private static void resetProcessedFeedItems() {
        processedFeedItemIds.clear();
        descriptionFeedItemIds.clear();
        casesWithDescriptionProcessed.clear();
    }
    
    @TestVisible
    private static void resetApiConfig() {
        apiConfig = null;
    }
}