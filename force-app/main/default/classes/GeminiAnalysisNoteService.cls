public with sharing class GeminiAnalysisNoteService {

    /**
     * Uses Attachment object instead of ContentVersion/ContentNote to avoid
     * UNSAFE_HTML_CONTENT errors when storing JSON with HTML sections.
     *
     * NOTE ON NEW AI SECTION KEYS:
     * This service persists and hydrates the full AnalysisBundleWrapper JSON
     * verbatim. Because `AnalysisBundleWrapper.sections` is a Map<String,String>,
     * new section keys emitted by the AI (e.g. chiefComplaint, keySymptoms,
     * allergies, currentMedications, medicalHistory, surgicalHistory,
     * familyHistory, socialHistory, physicalExam, labs, imaging, assessment,
     * differentialDiagnoses, treatmentPlan) are stored and returned without
     * any change here. The authoritative section allow-list lives in
     * GeminiFileInsightsController.SECTION_ORDER.
     */

    public static GeminiFileInsightsController.AnalysisBundleWrapper getStoredAnalysis(Id sourceContentDocumentId) {
        ContentVersion sourceVersion = getLatestSourceVersion(sourceContentDocumentId);
        if (sourceVersion == null) {
            return null;
        }

        Id parentRecordId = getParentRecordId(sourceContentDocumentId);
        String noteTitle = buildNoteTitle(sourceVersion.Title, sourceContentDocumentId);
        String legacyNoteTitle = buildLegacyNoteTitle(sourceVersion.Title, sourceContentDocumentId);
        Set<String> candidateNames = new Set<String>{ noteTitle, legacyNoteTitle };

        List<Attachment> attachments = [
            SELECT Id, Body, Name
            FROM Attachment
            WHERE ParentId = :parentRecordId
              AND Name IN :candidateNames
            ORDER BY LastModifiedDate DESC
        ];

        if (attachments.isEmpty()) {
            return null;
        }

        for (Attachment attachmentRow : attachments) {
            try {
                String jsonString = attachmentRow.Body.toString();
                GeminiFileInsightsController.AnalysisBundleWrapper bundle =
                    (GeminiFileInsightsController.AnalysisBundleWrapper)
                        JSON.deserialize(jsonString, GeminiFileInsightsController.AnalysisBundleWrapper.class);
                if (bundle == null
                    || String.isBlank(bundle.sourceDocumentId)
                    || bundle.sourceDocumentId == String.valueOf(sourceContentDocumentId)) {
                    return bundle;
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Failed to parse stored analysis: ' + e.getMessage());
            }
        }

        return null;
    }

    public static Boolean isAnalysisStale(Id sourceContentDocumentId) {
        GeminiFileInsightsController.AnalysisBundleWrapper bundle = getStoredAnalysis(sourceContentDocumentId);
        if (bundle == null) {
            return true;
        }

        if (String.isBlank(bundle.sourceLatestVersionId)) {
            return true;
        }

        ContentVersion latestSource = getLatestSourceVersion(sourceContentDocumentId);
        if (latestSource == null) {
            return true;
        }

        return bundle.sourceLatestVersionId != String.valueOf(latestSource.Id);
    }

    public static Boolean hasFreshAnalysis(Id sourceContentDocumentId) {
        return !isAnalysisStale(sourceContentDocumentId);
    }

    public static Id upsertAnalysisNote(
        Id sourceContentDocumentId,
        Id parentRecordId,
        GeminiFileInsightsController.AnalysisBundleWrapper bundle
    ) {
        ContentVersion sourceVersion = getLatestSourceVersion(sourceContentDocumentId);
        if (sourceVersion == null) {
            return null;
        }

        String noteTitle = buildNoteTitle(sourceVersion.Title, sourceContentDocumentId);
        Blob noteBlob = Blob.valueOf(JSON.serialize(bundle));

        // Delete any existing attachments for this analysis to enforce single-record lifecycle
        List<Attachment> existing = [
            SELECT Id
            FROM Attachment
            WHERE ParentId = :parentRecordId
              AND Name = :noteTitle
        ];

        if (!existing.isEmpty()) {
            delete existing;
        }

        // Insert fresh attachment
        Attachment att = new Attachment();
        att.ParentId = parentRecordId;
        att.Name = noteTitle;
        att.Body = noteBlob;
        att.ContentType = 'application/json';
        att.Description = 'AI Analysis Store - auto-generated';
        insert att;

        return att.Id;
    }

    // In-place body refresh for an existing analysis Attachment. Used after PDF
    // generation to record pdfDocumentId / pdfVersionId without delete-and-reinsert,
    // which would invalidate any Attachment Id we already handed off to a VF page.
    public static void updateAnalysisNoteBody(
        Id attachmentId,
        GeminiFileInsightsController.AnalysisBundleWrapper bundle
    ) {
        if (attachmentId == null || bundle == null) {
            return;
        }
        Attachment att = new Attachment(
            Id = attachmentId,
            Body = Blob.valueOf(JSON.serialize(bundle))
        );
        update att;
    }

    public static String buildNoteTitle(String sourceTitle, Id sourceContentDocumentId) {
        String suffix = ' - AI Analysis Store [' + String.valueOf(sourceContentDocumentId) + ']';
        String title = sourceTitle + suffix;
        if (title.length() > 255) {
            title = sourceTitle.left(255 - suffix.length()) + suffix;
        }
        return title;
    }

    @TestVisible
    private static String buildLegacyNoteTitle(String sourceTitle, Id sourceContentDocumentId) {
        String suffix = ' - AI Analysis Store [' + String.valueOf(sourceContentDocumentId).left(8) + ']';
        String title = sourceTitle + suffix;
        if (title.length() > 255) {
            title = sourceTitle.left(255 - suffix.length()) + suffix;
        }
        return title;
    }

    public static Id getParentRecordId(Id sourceContentDocumentId) {
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :sourceContentDocumentId
            ORDER BY SystemModstamp ASC
        ];
        
        Id fallbackParentId = null;
        for (ContentDocumentLink linkRow : links) {
            if (linkRow.LinkedEntityId == null
                || linkRow.LinkedEntityId.getSObjectType() == User.SObjectType) {
                continue;
            }
            
            if (linkRow.LinkedEntityId.getSObjectType() == Account.SObjectType) {
                return linkRow.LinkedEntityId;
            }
            if (fallbackParentId == null) {
                fallbackParentId = linkRow.LinkedEntityId;
            }
        }
        
        return fallbackParentId != null ? fallbackParentId : UserInfo.getUserId();
    }

    private static ContentVersion getLatestSourceVersion(Id sourceContentDocumentId) {
        List<ContentVersion> versions = [
            SELECT Id, Title, ContentDocumentId, FileType, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId = :sourceContentDocumentId
              AND IsLatest = true
            LIMIT 1
        ];

        return versions.isEmpty() ? null : versions[0];
    }
}