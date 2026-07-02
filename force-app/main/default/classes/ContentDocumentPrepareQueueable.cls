public class ContentDocumentPrepareQueueable implements Queueable {

    private List<Id> contentDocumentIds;

    public ContentDocumentPrepareQueueable(List<Id> contentDocumentIds) {
        this.contentDocumentIds = contentDocumentIds;
    }

    public void execute(QueueableContext qc) {

        BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
        if (apiConfig == null || String.isBlank(apiConfig.Api_Key__c)) return;
        
        Map<Id, ContentVersion> docToVersionMap = new Map<Id, ContentVersion>();
        Set<Id> metriportDocIds = new Set<Id>();
        
        for (ContentVersion cv : [
            SELECT Id,
                   ContentDocumentId,
                   Description,
                   Date__c,
                   Organization_Name__c,
                   Source_Type__c,
                   CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
              AND Source_Type__c = 'Metriport'
        ]) {
            if (!docToVersionMap.containsKey(cv.ContentDocumentId)) {
                docToVersionMap.put(cv.ContentDocumentId, cv);
                metriportDocIds.add(cv.ContentDocumentId);
            }
        }
        if (metriportDocIds.isEmpty()) {
        System.debug('No Metriport documents found to process');
        return;
    }


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
                   ContentDocument.LatestPublishedVersion.PathOnClient
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :metriportDocIds
        ];
        if (cdlList.isEmpty()) return;

        /* ---------- Create public URLs (DML) ---------- */
        Map<Id, String> publicUrlMap = new Map<Id, String>();

        for (ContentDocumentLink cdl : cdlList) {
            ContentVersion cv = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId = :cdl.ContentDocumentId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            ContentDistribution cd;

            List<ContentDistribution> existing = [
                SELECT Id, ContentDownloadUrl
                FROM ContentDistribution
                WHERE ContentVersionId = :cv.Id
                LIMIT 1
            ];

            if (!existing.isEmpty()) {
                cd = existing[0];
            } else {
                cd = new ContentDistribution(
                    Name = 'Public Link for API',
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
                    LIMIT 1
                ];
            }

            publicUrlMap.put(cdl.ContentDocumentId, cd.ContentDownloadUrl);

        }

        /* ---------- Map ContentDocument → Account ---------- */
        Map<Id, Id> docToAccountMap = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>();

        for (ContentDocumentLink cdl : cdlList) {
            if (cdl.LinkedEntityId != null &&
                cdl.LinkedEntityId.getSObjectType() == Account.sObjectType) {
                docToAccountMap.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                accountIds.add(cdl.LinkedEntityId);
            }
        }

        /* ---------- Map Account → Contact ---------- */
        Map<Id, Id> accountToContactMap = new Map<Id, Id>();
        if (!accountIds.isEmpty()) {
            for (Contact c : [
                SELECT Id, AccountId
                FROM Contact
                WHERE AccountId IN :accountIds
                LIMIT 1
            ]) {
                accountToContactMap.put(c.AccountId, c.Id);
            }
        }

     /*   Map<Id, ContentVersion> docToVersionMap = new Map<Id, ContentVersion>();

            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId, Description, Date__c, Organization_Name__c
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                ORDER BY CreatedDate DESC
            ]) {
                if (!docToVersionMap.containsKey(cv.ContentDocumentId)) {
                    docToVersionMap.put(cv.ContentDocumentId, cv);
                }
            } */


        /* ---------- Build payload EXACTLY like original ---------- */
        Map<Id, List<Map<String, Object>>> accountDocumentsMap = new Map<Id, List<Map<String, Object>>>();
        Set<Id> processedDocs = new Set<Id>();

        for (ContentDocumentLink cdl : cdlList) {
            if (processedDocs.contains(cdl.ContentDocumentId)) continue;
            processedDocs.add(cdl.ContentDocumentId);

            Map<String, Object> doc = new Map<String, Object>();
            ContentVersion latestCv = docToVersionMap.get(cdl.ContentDocumentId);
            doc.put('ContentDocumentId', cdl.ContentDocumentId);
            doc.put('Id', cdl.Id);
            doc.put('ShareType', cdl.ShareType);
            doc.put('Visibility', cdl.Visibility);

            doc.put('Title', cdl.ContentDocument.Title);
            doc.put('FileType', cdl.ContentDocument.FileType);
            doc.put('FileExtension', cdl.ContentDocument.FileExtension);
            doc.put('ContentSize', cdl.ContentDocument.ContentSize);
            doc.put('CreatedDate', latestcv.Date__c);
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

        /* ---------- Serialize payloads (IMPORTANT) ---------- */
        List<String> payloads = new List<String>();

        for (Id accountId : accountDocumentsMap.keySet()) {
            Map<String, Object> payload = new Map<String, Object>();
            if (accountToContactMap.containsKey(accountId)) {
                payload.put('contactId', accountToContactMap.get(accountId));
            }
            payload.put('documents', accountDocumentsMap.get(accountId));

            payloads.add(JSON.serialize(payload));
        }

        /* ---------- Chain Queueable #2 ---------- */
         if (!Test.isRunningTest()) {
        System.enqueueJob(
            new ContentDocumentQueueable(payloads)
        );
         }
        System.debug('CDQueue In Prepare' +payloads);
    }
}