public class DocumentProcessingPipelineQueueable implements Queueable, Database.AllowsCallouts {

    
    private String step;
    private Id logRecordId;
    private Id contentVersionId;

    
    public DocumentProcessingPipelineQueueable(String step, Id logRecordId, Id contentVersionId) {
        this.step             = step;
        this.logRecordId      = logRecordId;
        this.contentVersionId = contentVersionId;
    }

    public void execute(QueueableContext context) {

        System.debug('DocumentProcessingPipelineQueueable :: step=' + step + ' | cvId=' + contentVersionId);

        if (step == 'ATTACHMENT') {
            handleAttachment();
        } else if (step == 'AI_NAMING') {
            handleAiNaming();
        } else if (step == 'AI_SUMMARY') {
            handleAiSummary();
        } else if (step == 'GDRIVE') {
            handleGdrive();
        }
    }

    // ── Step 1: Attachment ────────────────────────────────────────────────────

    private void handleAttachment() {

        ContentVersion cv = [
            SELECT Title, Description, Source_Type__c,
                   Organization_Name__c, Service_Date_Time__c,
                   PathOnClient, FileType
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        Map<String, Object> payload = new Map<String, Object>{
            'contentVersionId'  => contentVersionId,
            'title'             => cv.Title,
            'description'       => cv.Description,
            'source'            => cv.Source_Type__c,
            'organizationName'  => cv.Organization_Name__c,
            'serviceDatetime'   => cv.Service_Date_Time__c != null
                                       ? String.valueOf(cv.Service_Date_Time__c)
                                       : null,
            'fileType'          => cv.FileType,
            'pathOnClient'      => cv.PathOnClient
        };

        // AttachmentService sets Ready_for_Ai_Naming__c = true on success
        AttachmentService.createAttachment(JSON.serialize(payload), contentVersionId);
    }

    // ── Step 2: AI Naming ─────────────────────────────────────────────────────

    private void handleAiNaming() {
        // AiFileNamingDailyJob.finish() sets Ready_for_Ai_Summery__c = true
        Database.executeBatch(new AiFileNamingDailyJob(contentVersionId), 1);
    }

    // ── Step 3: AI Summary ────────────────────────────────────────────────────

    private void handleAiSummary() {
        // GeminiFileInsightBackfillBatch.finish() sets Ready_for_Gdrive__c = true
        Database.executeBatch(
            new GeminiFileInsightBackfillBatch(true, false, contentVersionId),
            1
        );
    }

    // ── Step 4: Google Drive Sync ─────────────────────────────────────────────

    private void handleGdrive() {
        List<ContentVersion> uploadableVersions = getUploadableDriveVersions();
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentVersion cv : uploadableVersions) {
            contentDocumentIds.add(cv.ContentDocumentId);
        }

        if (contentDocumentIds.isEmpty()) return;

        fra__File_Sync_Job__c job = new fra__File_Sync_Job__c(
            fra__Batch_Status__c    = 'Queued',
            fra__Object_API_Name__c = 'ContentDocument',
            fra__Sync_ContentVersion__c = true,
            fra__Sync_Attachment__c     = false
        );
        insert job;

        List<String> docIdStrings = new List<String>();
        for (Id docId : contentDocumentIds) {
            docIdStrings.add('\'' + String.escapeSingleQuotes(String.valueOf(docId)) + '\'');
        }

        String q =
            'SELECT Id FROM ContentDocument WHERE Id IN (' +
            String.join(docIdStrings, ',') + ')';

        Database.executeBatch(
            new fra.FileSyncBatch('ContentDocument', job.Id, true, false, 100, q, 'Google Drive', null),
            1
        );

        System.debug('GDRIVE sync started for ContentVersion: ' + contentVersionId);
    }

    @TestVisible
    private List<ContentVersion> getUploadableDriveVersions() {
        List<Document_Processing_Log__c> logs = [
            SELECT Id,
                   Main_File_Storage_Record_Id__c,
                   AI_Summary_File_Storage_Record_Id__c,
                   Drive_Sync_Completed_On__c
            FROM Document_Processing_Log__c
            WHERE Id = :logRecordId
            LIMIT 1
        ];

        if (!logs.isEmpty()
            && logs[0].Drive_Sync_Completed_On__c != null
            && String.isNotBlank(logs[0].Main_File_Storage_Record_Id__c)
            && String.isNotBlank(logs[0].AI_Summary_File_Storage_Record_Id__c)) {
            System.debug('GDRIVE sync skipped because both canonical files are already uploaded. LogId=' + logRecordId);
            return new List<ContentVersion>();
        }

        List<ContentVersion> sourceVersions = [
            SELECT Id, ContentDocumentId, Title, FileType, Source_Type__c, Related_File__c
            FROM ContentVersion
            WHERE Id = :contentVersionId
            AND IsLatest = true
            AND Source_Type__c = 'Metriport'
            AND FileType = 'PDF'
            LIMIT 1
        ];

        if (sourceVersions.isEmpty()) {
            System.debug('GDRIVE sync skipped because source ContentVersion is not a latest Metriport PDF. ContentVersionId=' + contentVersionId);
            return new List<ContentVersion>();
        }

        ContentVersion sourceVersion = sourceVersions[0];
        List<ContentVersion> selected = new List<ContentVersion>();

        if (logs.isEmpty() || String.isBlank(logs[0].Main_File_Storage_Record_Id__c)) {
            selected.add(sourceVersion);
        }

        List<ContentVersion> aiSummaryVersions = [
            SELECT Id, ContentDocumentId, Title, FileType, Source_Type__c, Related_File__c
            FROM ContentVersion
            WHERE Related_File__c = :sourceVersion.ContentDocumentId
            AND IsLatest = true
            AND Source_Type__c = 'AI'
            AND FileType = 'PDF'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!aiSummaryVersions.isEmpty()
            && (logs.isEmpty() || String.isBlank(logs[0].AI_Summary_File_Storage_Record_Id__c))) {
            selected.add(aiSummaryVersions[0]);
        }

        return selected;
    }
}