public class CDPortalPrepareQueueable implements Queueable {
    private List<Id> contentDocumentIds;
    public CDPortalPrepareQueueable(List<Id> contentDocumentIds) {
        this.contentDocumentIds = contentDocumentIds;
    }
    public void execute(QueueableContext qc) {
        BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
        if (apiConfig == null || String.isBlank(apiConfig.Api_Key__c)) return;
        Map<Id, ContentVersion> docToVersionMap = new Map<Id, ContentVersion>();
        for (ContentVersion cv : [
            SELECT Id,
                   ContentDocumentId,
                   Description,
                   Service_Date_Time__c,
                   Organization_Name__c,
                   CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!docToVersionMap.containsKey(cv.ContentDocumentId)) {
                docToVersionMap.put(cv.ContentDocumentId, cv);
            }
        }
        if(docToVersionMap.isEmpty()) return;
        List<ContentDocumentLink> cdlList = [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility,
                   ContentDocument.Title,
                   ContentDocument.FileType,
                   ContentDocument.FileExtension,
                   ContentDocument.ContentSize,
                   ContentDocument.CreatedDate,
                   ContentDocument.CreatedById,
                   ContentDocument.LastModifiedDate,
                   ContentDocument.LastModifiedById,
                   ContentDocument.OwnerId,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.LatestPublishedVersion.VersionNumber,
                   ContentDocument.LatestPublishedVersion.PathOnClient,
                   ContentDocument.LatestPublishedVersion.Related_File__c
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocumentIds];  
        if (cdlList.isEmpty()) return;
        Map<Id, String> publicUrlMap = new Map<Id, String>();
        for (ContentVersion cv : docToVersionMap.values()) {
            ContentDistribution cd = new ContentDistribution(
                Name = 'Portal Public Link',
                ContentVersionId = cv.Id,
                PreferencesAllowOriginalDownload = true,
                PreferencesAllowPDFDownload = true,
                PreferencesNotifyOnVisit = false,
                PreferencesPasswordRequired = false,
                PreferencesLinkLatestVersion = true
            );
            insert cd;
            cd = [
                SELECT ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id = :cd.Id
                LIMIT 1];
            publicUrlMap.put(cv.ContentDocumentId, cd.ContentDownloadUrl);
        }
        Map<Id, Id> docToAccountMap = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>();
        for (ContentDocumentLink cdl : cdlList) {
            if (cdl.LinkedEntityId != null &&
                cdl.LinkedEntityId.getSObjectType() == Account.sObjectType) {

                docToAccountMap.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                accountIds.add(cdl.LinkedEntityId);
            }
        }
        Map<Id, Id> accountToContactMap = new Map<Id, Id>();
        if (!accountIds.isEmpty()) {
            for (Contact c : [
                SELECT Id, AccountId
                FROM Contact
                WHERE AccountId IN :accountIds
            ]) {
                if(!accountToContactMap.containsKey(c.AccountId)) {
                    accountToContactMap.put(c.AccountId, c.Id);
                }
            }
        }
        Map<Id, List<Map<String, Object>>> accountDocumentsMap =
            new Map<Id, List<Map<String, Object>>>();
        Set<Id> processedDocs = new Set<Id>();
        for (ContentDocumentLink cdl : cdlList) {
            if (processedDocs.contains(cdl.ContentDocumentId)) continue;
            processedDocs.add(cdl.ContentDocumentId);
            Map<String, Object> doc = new Map<String, Object>();
            ContentVersion latestCv = docToVersionMap.get(cdl.ContentDocumentId);
            doc.put('ContentDocumentId', cdl.ContentDocumentId);  
            doc.put('Id', latestCv != null ? latestCv.Id : '');  
            doc.put('ShareType', cdl.ShareType);
            doc.put('Visibility', cdl.Visibility);
            doc.put('Title', cdl.ContentDocument.Title);
            doc.put('FileType', cdl.ContentDocument.FileType);
            doc.put('FileExtension', cdl.ContentDocument.FileExtension);
            doc.put('ContentSize', cdl.ContentDocument.ContentSize);
            doc.put('CreatedDate', latestCv != null ? latestCv.Service_Date_Time__c : null);
            doc.put('CreatedById', cdl.ContentDocument.CreatedById);
            doc.put('LastModifiedDate', cdl.ContentDocument.LastModifiedDate);
            doc.put('LastModifiedById', cdl.ContentDocument.LastModifiedById);
            doc.put('OwnerId', cdl.ContentDocument.OwnerId);
            doc.put('LatestPublishedVersionId', cdl.ContentDocument.LatestPublishedVersionId);
            doc.put('PublicUrl', publicUrlMap.get(cdl.ContentDocumentId));
            doc.put('VersionNumber',
                String.valueOf(cdl.ContentDocument.LatestPublishedVersion.VersionNumber));
            doc.put('PathOnClient',
                cdl.ContentDocument.LatestPublishedVersion.PathOnClient);
            doc.put('relatedFile',
                cdl.ContentDocument.LatestPublishedVersion.Related_File__c);
            if (latestCv != null) {
                doc.put('Description', latestCv.Description);
                doc.put('Organization', latestCv.Organization_Name__c);
            }
            Id accountId = docToAccountMap.get(cdl.ContentDocumentId);
            if (accountId != null) {
                if (!accountDocumentsMap.containsKey(accountId)) {
                    accountDocumentsMap.put(accountId, new List<Map<String, Object>>());
                }
                accountDocumentsMap.get(accountId).add(doc);
            }
        }
        List<String> payloads = new List<String>();
        for (Id accountId : accountDocumentsMap.keySet()) {
            Map<String, Object> payload = new Map<String, Object>();
            if (accountToContactMap.containsKey(accountId)) {
                payload.put('contactId', accountToContactMap.get(accountId));
            }
            payload.put('documents', accountDocumentsMap.get(accountId));
            payloads.add(JSON.serialize(payload));
            System.debug('payload >> ' + JSON.serializePretty(payload));
        }
        if (!Test.isRunningTest() && !payloads.isEmpty()) {
            System.enqueueJob(
                new ContentDocumentQueueable(payloads)  
            );
        }
    }
}