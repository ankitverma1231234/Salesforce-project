public with sharing class GeminiFileInsightBackfillBatch 
implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    private final Boolean forceRegenerate;
    private Id contentVersionId;
    
    @TestVisible private Integer totalProcessed = 0;
    @TestVisible private Integer totalSuccess   = 0;
    @TestVisible private Integer totalSkipped   = 0;
    @TestVisible private Integer totalFailed    = 0;
    
    public GeminiFileInsightBackfillBatch(
        Boolean forceRegenerate,
        Boolean attachPdf,
        Id contentVersionId
    ) {
        this.forceRegenerate = forceRegenerate == true;
        this.contentVersionId = contentVersionId;
    }
      public GeminiFileInsightBackfillBatch(Boolean forceRegenerate, Boolean attachPdf) {
        this.forceRegenerate = forceRegenerate == true;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        String query =
            'SELECT Id, ContentDocumentId, Title, FileType ' +
            'FROM ContentVersion ' +
            'WHERE IsLatest = true ' +
            'AND Source_Type__c = \'Metriport\' ' +
            (forceRegenerate ? '' : 'AND is_AI_Summary_Generated__c = false ') +
            'AND AI_Name_Generated__c = true ' +
            'AND (NOT Title LIKE \'%AI Generated Summary%\') ' +
            'AND FileType != \'TIF\' ' +
            'AND FirstPublishLocationId IN (SELECT Id FROM Account)';
        
        // Agar specific Id pass hui hai to uska filter add karo
        if (contentVersionId != null) {
            query += ' AND Id = :contentVersionId';
        }
        
        return Database.getQueryLocator(query);
    }
    
    
    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        
        Set<Id> docIds = new Set<Id>();
        for (ContentVersion cv : scope) {
            docIds.add(cv.ContentDocumentId);
        }
        
        Set<Id> accountLinkedDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :docIds
        ]) {
            String linkedId = String.valueOf(cdl.LinkedEntityId);
            if (linkedId != null && linkedId.startsWith('001')) {
                accountLinkedDocIds.add(cdl.ContentDocumentId);
            }
        }
        
        // Skip sources that already have an AI summary file linked.
        // Re-running would invoke upsertAnalysisPdfToParent's delete DML, which fires
        // ContentDocumentDeleteTrigger and chains into a future callout that cannot
        // be enqueued reliably from this batch context (callout slot already used).
        Set<Id> docIdsWithExistingAi = new Set<Id>();
        for (ContentVersion aiCv : [
            SELECT Related_File__c
            FROM ContentVersion
            WHERE Related_File__c IN :docIds
            AND Source_Type__c = 'AI'
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
            
            if (docIdsWithExistingAi.contains(docId)) {
                totalSkipped++;
                logger.logSkippedHasExistingAi(cv.Id, docId);
                continue;
            }
            
            Long startTime = System.currentTimeMillis();
            try {
                GeminiFileInsightsController.generateFullAnalysis(
                    docId,
                    forceRegenerate,
                    false,
                    true
                );
                
                totalSuccess++;
                logger.logSuccess(
                    cv.Id,
                    docId,
                    cv.Title != null ? cv.Title + ' - AI Generated Summary' : null,
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
        
        if (totalFailed > 0) {
        }
        if (totalProcessed == 0) {
        }
        if (totalProcessed > 0) {
            
            // GeminiFileInsightPdfBackfillBatch
            //  GeminiFileInsightPdfBackfillBatch batch = new GeminiFileInsightPdfBackfillBatch(true);
            // Database.executeBatch(batch, 1);
            
            
            Database.executeBatch(
                new GeminiFileInsightPdfBackfillBatch(true, contentVersionId),
                1
            );
            
        }
    }
}