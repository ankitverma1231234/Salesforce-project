public with sharing class GeminiFileInsightPdfBackfillBatch
implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    private final Boolean forceRegeneratePdf;
    private Id contentVersionId;
    
    @TestVisible private Integer totalProcessed = 0;
    @TestVisible private Integer totalSuccess   = 0;
    @TestVisible private Integer totalSkipped   = 0;
    @TestVisible private Integer totalFailed    = 0;
    
    public GeminiFileInsightPdfBackfillBatch() {
        this(false, null);
    }
    
    public GeminiFileInsightPdfBackfillBatch(Boolean forceRegeneratePdf) {
        this(forceRegeneratePdf, null);
    }
    
    public GeminiFileInsightPdfBackfillBatch(
        Boolean forceRegeneratePdf,
        Id contentVersionId
    ) {
        this.forceRegeneratePdf = forceRegeneratePdf == true;
        this.contentVersionId = contentVersionId;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        String query =
            'SELECT Id, ContentDocumentId, Title, FileType ' +
            'FROM ContentVersion ' +
            'WHERE IsLatest = true ' +
            'AND Source__c = \'Metriport\' ' +
            'AND is_AI_Summary_Generated__c = false ' +
            'AND (NOT Title LIKE \'%AI Generated Summary%\') ' +
            'AND FileType != \'TIF\' ' +
            'AND FirstPublishLocationId IN (SELECT Id FROM Account)';
        
        // Agar Id pass hui hai to sirf wahi record process hoga
        if (contentVersionId != null) {
            query += ' AND Id = :contentVersionId';
        }
        
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        Set<Id> docIds = new Set<Id>();
        for (ContentVersion cv : scope) {
            if (cv.ContentDocumentId != null) {
                docIds.add(cv.ContentDocumentId);
            }
        }
        
        Set<Id> accountLinkedDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :docIds
        ]) {
            if (cdl.LinkedEntityId != null
                && cdl.LinkedEntityId.getSObjectType() == Account.SObjectType) {
                    accountLinkedDocIds.add(cdl.ContentDocumentId);
                }
        }
        
        Set<Id> docIdsWithExistingAi = new Set<Id>();
        for (ContentVersion aiCv : [
            SELECT Related_File__c
            FROM ContentVersion
            WHERE Related_File__c IN :docIds
            AND Source__c = 'AI'
            AND IsLatest = true
        ]) {
            if (aiCv.Related_File__c != null) {
                docIdsWithExistingAi.add(aiCv.Related_File__c);
            }
        }
        
        String jobId = bc != null ? String.valueOf(bc.getJobId()) : null;
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger(jobId);
        
        for (ContentVersion cv : scope) {
            totalProcessed++;
            Id docId = cv.ContentDocumentId;
            
            if (!accountLinkedDocIds.contains(docId)) {
                totalSkipped++;
                logger.logSkippedNoAccount(cv.Id, docId);
                continue;
            }
            
            if (!forceRegeneratePdf && docIdsWithExistingAi.contains(docId)) {
                totalSkipped++;
                logger.logSkippedHasExistingAi(cv.Id, docId);
                continue;
            }
            
            GeminiFileInsightsController.AnalysisBundleWrapper stored =
                GeminiAnalysisNoteService.getStoredAnalysis(docId);
            if (stored == null || stored.sourceLatestVersionId != String.valueOf(cv.Id)) {
                totalSkipped++;
                continue;
            }
            
            Long startTime = System.currentTimeMillis();
            try {
                GeminiFileInsightsController.SavedFileResult saved =
                    GeminiPdfSyncService.syncPdfFromStoredAnalysis(docId);
                
                totalSuccess++;
                logger.logSuccess(
                    cv.Id,
                    docId,
                    saved != null ? saved.title : null,
                    System.currentTimeMillis() - startTime
                );
            } catch (Exception e) {
                totalFailed++;
                logger.logFailure(cv.Id, docId, e, System.currentTimeMillis() - startTime);
            }
        }
        
        logger.flush();
    }
    
    public void finish(Database.BatchableContext bc) {

        if (contentVersionId == null) return;

        // Flip Ready_for_Gdrive__c → trigger fires GDRIVE queueable step
        List<Document_Processing_Log__c> logs = [
            SELECT Id
            FROM Document_Processing_Log__c
            WHERE Content_Version_Id__c = :contentVersionId
            LIMIT 1
        ];

        if (!logs.isEmpty()) {
            logs[0].Ready_for_Gdrive__c = true;
            update logs[0];
        }
    }
}