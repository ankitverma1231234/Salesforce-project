public with sharing class AccountFileUploaderController {

    @AuraEnabled
    public static UploadResult confirmUpload(
        Id accountId,
        List<Id> contentDocumentIds,
        String uploadMetadataJson
    ) {
        UploadMetadata uploadMetadata = (UploadMetadata) JSON.deserialize(
            uploadMetadataJson,
            UploadMetadata.class
        );

        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            throw new AuraHandledException('At least one ContentDocumentId is required.');
        }

        List<Account> accounts = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }

        Set<Id> existingLinkedDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId  = :accountId
              AND ContentDocumentId IN :contentDocumentIds
        ]) {
            existingLinkedDocIds.add(cdl.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (Id docId : contentDocumentIds) {
            if (!existingLinkedDocIds.contains(docId)) {
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId  = docId;
                cdl.LinkedEntityId     = accountId;
                cdl.ShareType          = 'V';
                cdl.Visibility         = 'AllUsers';
                linksToInsert.add(cdl);
            }
        }
        if (!linksToInsert.isEmpty()) {
            try {
                insert linksToInsert;
            } catch (DmlException e) {
                throw new AuraHandledException(
                    'Unable to link uploaded file(s) to the Account: ' + e.getMessage()
                );
            }
        }

        // ── Fetch the latest ContentVersion(s) for the uploaded documents ─────
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, FileType, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
              AND IsLatest = true
        ];

        
        applyUploadMetadata(versions, uploadMetadata);

        // ── Build result ──────────────────────────────────────────────────────
        UploadResult result  = new UploadResult();
        result.accountId     = accountId;
        result.accountName   = accounts[0].Name;
        result.uploadedFiles = new List<UploadedFile>();

        List<Id> versionIds = new List<Id>();
        for (ContentVersion cv : versions) {
            UploadedFile uf      = new UploadedFile();
            uf.contentVersionId  = cv.Id;
            uf.contentDocumentId = cv.ContentDocumentId;
            uf.title             = cv.Title;
            uf.fileType          = cv.FileType;
            uf.contentSize       = cv.ContentSize;
            result.uploadedFiles.add(uf);
            versionIds.add(cv.Id);
        }

        // ── Create processing logs ────────────────────────────────────────────
        LogCreationResult logResult = createProcessingLogs(versionIds);
        result.logsCreated          = logResult.created;
        result.logsSkipped          = logResult.skippedExisting;
        result.logCreationFailed    = logResult.failed;
        result.logCreationError     = logResult.errorMessage;

        if (logResult.failed) {
            throw new AuraHandledException(
                'File(s) uploaded, but the document processing log could not be created: ' +
                logResult.errorMessage
            );
        }

        // ── Sync content documents to external service ────────────────────────
        AccountFileExternalSyncService.SyncResult syncResult =
        AccountFileExternalSyncService.queueContentDocumentSync(contentDocumentIds);
        result.syncQueued           = syncResult.queued;
        result.syncJobId            = syncResult.jobId;
        result.syncFailed           = syncResult.failed;
        result.syncError            = syncResult.errorMessage;
        result.syncSkippedDuplicate = syncResult.skippedDuplicate;

        DateTime scheduledTime = DateTime.now().addMinutes(2);
        String cronExp = String.format(
            '0 {0} {1} {2} {3} ? {4}',
            new List<String>{
                String.valueOf(scheduledTime.minute()),
                String.valueOf(scheduledTime.hour()),
                String.valueOf(scheduledTime.day()),
                String.valueOf(scheduledTime.month()),
                String.valueOf(scheduledTime.year())
            }
        );
        System.schedule(
            'FileStoragePublicUrlBackfillBatch_' + DateTime.now().getTime(),
            cronExp,
            new FileStoragePublicUrlBackfillBatch(false, System.now())
        );

        return result;
    }

    private static void applyUploadMetadata(
        List<ContentVersion> versions,
        UploadMetadata uploadMetadata
    ) {
        if (versions == null || versions.isEmpty() || uploadMetadata == null) return;

        String title       = normalize(uploadMetadata.title);
        String sourceType  = normalize(uploadMetadata.sourceType);
        String category    = normalize(uploadMetadata.category);
        String description = normalize(uploadMetadata.description);

        Datetime serviceDateTime = null;
        if (String.isNotBlank(uploadMetadata.serviceDateTime)) {
            try {
                serviceDateTime = (Datetime) JSON.deserialize(
                    '"' + uploadMetadata.serviceDateTime + '"',
                    Datetime.class
                );
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'applyUploadMetadata: could not parse serviceDateTime "'
                    + uploadMetadata.serviceDateTime + '": ' + e.getMessage());
            }
        }

        List<ContentVersion> toUpdate = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            ContentVersion upd = new ContentVersion(Id = cv.Id);
            Boolean changed    = false;

            if (String.isNotBlank(title)) {
                upd.Title = title;
                cv.Title  = title;
                changed   = true;
            }
            if (String.isNotBlank(sourceType)) {
                upd.Source_Type__c = sourceType;
                changed = true;
            }
            if (String.isNotBlank(category)) {
                upd.Category__c = category;
                changed = true;
            }
            if (String.isNotBlank(description)) {
                upd.Description = description;
                cv.Description  = description;
                changed         = true;
            }
            if (serviceDateTime != null) {
                upd.Service_Date_Time__c = serviceDateTime;
                changed = true;
            }

            if (changed) toUpdate.add(upd);
        }

        if (toUpdate.isEmpty()) return;

        try {
            update toUpdate;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Unable to update file details: ' + e.getMessage()
            );
        }
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    // ── Create Document_Processing_Log__c records (skip duplicates) ───────────
    private static LogCreationResult createProcessingLogs(List<Id> contentVersionIds) {
        LogCreationResult res = new LogCreationResult();
        res.created         = 0;
        res.skippedExisting = 0;
        res.failed          = false;

        if (contentVersionIds == null || contentVersionIds.isEmpty()) return res;

        Set<String> versionIdStrings = new Set<String>();
        for (Id vid : contentVersionIds) versionIdStrings.add(String.valueOf(vid));

        Set<String> existingVersionIds = new Set<String>();
        for (Document_Processing_Log__c existing : [
            SELECT Content_Version_Id__c
            FROM Document_Processing_Log__c
            WHERE Content_Version_Id__c IN :versionIdStrings
        ]) {
            existingVersionIds.add(existing.Content_Version_Id__c);
        }

        List<Document_Processing_Log__c> logsToInsert = new List<Document_Processing_Log__c>();
        for (Id versionId : contentVersionIds) {
            String versionIdStr = String.valueOf(versionId);
            if (existingVersionIds.contains(versionIdStr)) {
                res.skippedExisting++;
                continue;
            }
            Document_Processing_Log__c log = new Document_Processing_Log__c();
            log.Content_Version_Id__c   = versionIdStr;
            log.Is_Active__c            = true;
            log.Ready_for_Attachment__c = true;
            logsToInsert.add(log);
        }

        if (logsToInsert.isEmpty()) return res;

        try {
            insert logsToInsert;
            res.created = logsToInsert.size();
        } catch (DmlException e) {
            res.failed       = true;
            res.errorMessage = e.getDmlMessage(0) != null ? e.getDmlMessage(0) : e.getMessage();
        } 

        return res;
    }

    // ── Inner classes ─────────────────────────────────────────────────────────

    public class UploadResult {
        @AuraEnabled public Id                 accountId;
        @AuraEnabled public String             accountName;
        @AuraEnabled public List<UploadedFile> uploadedFiles;
        @AuraEnabled public Integer            logsCreated;
        @AuraEnabled public Integer            logsSkipped;
        @AuraEnabled public Boolean            logCreationFailed;
        @AuraEnabled public String             logCreationError;
        @AuraEnabled public Boolean            syncQueued;
        @AuraEnabled public String             syncJobId;
        @AuraEnabled public Boolean            syncFailed;
        @AuraEnabled public String             syncError;
        @AuraEnabled public Boolean            syncSkippedDuplicate;
    }

    public class UploadedFile {
        @AuraEnabled public Id      contentVersionId;
        @AuraEnabled public Id      contentDocumentId;
        @AuraEnabled public String  title;
        @AuraEnabled public String  fileType;
        @AuraEnabled public Integer contentSize;
    }

    public class UploadMetadata {
        @AuraEnabled public String title;
        @AuraEnabled public String documentType;
        @AuraEnabled public String serviceDateTime;
        @AuraEnabled public String description;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String category;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    private class LogCreationResult {
        Integer created;
        Integer skippedExisting;
        Boolean failed;
        String  errorMessage;
    }
}