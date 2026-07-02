public with sharing class GeminiPdfSyncService {
    public class GeminiPdfSyncException extends Exception {}

    private static Exception buildHandledException(String message) {
        if (System.isBatch()) {
            return new GeminiPdfSyncException(message);
        }
        return new AuraHandledException(message);
    }

    public static GeminiFileInsightsController.SavedFileResult syncPdfFromStoredAnalysis(Id sourceContentDocumentId) {
        GeminiFileInsightsController.AnalysisBundleWrapper stored =
            GeminiAnalysisNoteService.getStoredAnalysis(sourceContentDocumentId);

        if (stored == null) {
            throw buildHandledException('No saved AI note found for this file. Run analysis first.');
        }

        // Pre-flight content check — if the stored bundle is empty, the VF page
        // would render the "No AI analysis data was available" empty state.
        // Flip Is_AI_Summary_Generated__c to false so the retry mechanism picks
        // it up, and bail before consuming a getContentAsPDF() call.
        if (!GeminiFileInsightsController.bundleHasRenderableContent(stored)) {
            List<ContentVersion> srcVers = [
                SELECT Id FROM ContentVersion
                WHERE ContentDocumentId = :sourceContentDocumentId AND IsLatest = true LIMIT 1
            ];
            if (!srcVers.isEmpty()) {
                try {
                    update new ContentVersion(Id = srcVers[0].Id, Is_AI_Summary_Generated__c = false);
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Failed to flag source for retry: ' + e.getMessage());
                }
            }
            throw buildHandledException('AI data capture failed: stored analysis was empty. Source file marked for retry.');
        }

        String analysisTitle = stored.analysisTitle;
        if (String.isBlank(analysisTitle)) {
            ContentVersion cv = [
                SELECT Title FROM ContentVersion
                WHERE ContentDocumentId = :sourceContentDocumentId AND IsLatest = true LIMIT 1
            ];
            analysisTitle = cv.Title + ' - AI Summary';
        }

        // Best-effort cache populate (no-op if partition is missing)
        String analysisJson = JSON.serialize(stored);
        GeminiCacheManager.putAnalysis(sourceContentDocumentId, analysisJson);

        Id parentRecordId = GeminiAnalysisNoteService.getParentRecordId(sourceContentDocumentId);

        // Re-write the analysis Attachment so we have a known, committed Id to hand
        // to the VF page. getContentAsPDF() runs in a separate transaction, so any
        // in-memory or uncommitted state is invisible there — direct-by-Id read is
        // the only path immune to that and to platform-cache absence.
        Id analysisAttachmentId = GeminiAnalysisNoteService.upsertAnalysisNote(
            sourceContentDocumentId, parentRecordId, stored
        );

        PageReference pageRef = Page.GeminiFileInsightsPdf;
        pageRef.getParameters().put('contentDocumentId', String.valueOf(sourceContentDocumentId));
        if (analysisAttachmentId != null) {
            pageRef.getParameters().put('analysisAttachmentId', String.valueOf(analysisAttachmentId));
        }

        Blob pdfBlob = Test.isRunningTest() ? Blob.valueOf('Test PDF') : pageRef.getContentAsPDF();

        // Delete any existing AI Summary ContentDocument(s) for this source to
        // enforce a single AI-generated PDF per source ContentDocument.
        List<ContentVersion> existingAiVersions = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Related_File__c = :sourceContentDocumentId
              AND Source_Type__c = 'AI'
              AND IsLatest = true
        ];

        if (!existingAiVersions.isEmpty()) {
            Set<Id> docIdsToDelete = new Set<Id>();
            for (ContentVersion aiVersion : existingAiVersions) {
                docIdsToDelete.add(aiVersion.ContentDocumentId);
            }
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docIdsToDelete];
        }

        List<ContentVersion> sourceVersions = [
            SELECT Id, Service_Date_Time__c, Send_File_to_Portal__c
            FROM ContentVersion
            WHERE ContentDocumentId = :sourceContentDocumentId
              AND IsLatest = true
            LIMIT 1
        ];

        // Create fresh ContentVersion + ContentDocument
        ContentVersion newVersion = new ContentVersion();
        newVersion.Title = analysisTitle;
        newVersion.PathOnClient = analysisTitle + '.pdf';
        newVersion.VersionData = pdfBlob;
        newVersion.IsMajorVersion = true;
        newVersion.Description = 'Auto-generated AI summary PDF';
        newVersion.Related_File__c = sourceContentDocumentId;
        newVersion.FirstPublishLocationId = parentRecordId;
        newVersion.Source_Type__c = 'AI';

        if (!sourceVersions.isEmpty()) {
            newVersion.Service_Date_Time__c = sourceVersions[0].Service_Date_Time__c;
            newVersion.Send_File_to_Portal__c = sourceVersions[0].Send_File_to_Portal__c;
        }

        insert newVersion;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :newVersion.Id
            LIMIT 1
        ];

        GeminiFileInsightsController.SavedFileResult result = new GeminiFileInsightsController.SavedFileResult();
        result.contentVersionId = insertedVersion.Id;
        result.contentDocumentId = insertedVersion.ContentDocumentId;
        result.title = analysisTitle;

        stored.pdfDocumentId = String.valueOf(insertedVersion.ContentDocumentId);
        stored.pdfVersionId = String.valueOf(insertedVersion.Id);
        stored.analysisDocumentId = String.valueOf(insertedVersion.ContentDocumentId);
        stored.analysisVersionId = String.valueOf(insertedVersion.Id);
        GeminiAnalysisNoteService.updateAnalysisNoteBody(analysisAttachmentId, stored);

        if (!sourceVersions.isEmpty()) {
            update new ContentVersion(
                Id = sourceVersions[0].Id,
                Is_AI_Summary_Generated__c = true
            );
        }

        return result;
    }
}