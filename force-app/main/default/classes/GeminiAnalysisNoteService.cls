public with sharing class GeminiAnalysisNoteService {
    private static Integer STORED_ANALYSIS_EXACT_LIMIT = 10;
    private static Integer STORED_ANALYSIS_LEGACY_LIMIT = 10;

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

        Set<Id> parentIds = getAnalysisParentIds(sourceContentDocumentId);
        String notePattern = buildNoteTitlePattern(sourceContentDocumentId);
        String legacyNotePattern = buildLegacyNoteTitlePattern(sourceContentDocumentId);

        List<Attachment> exactCandidates = [
            SELECT Id, Name
            FROM Attachment
            WHERE ParentId IN :parentIds
              AND Name LIKE :notePattern
            ORDER BY LastModifiedDate DESC, CreatedDate DESC, Id DESC
            LIMIT :STORED_ANALYSIS_EXACT_LIMIT
        ];

        GeminiFileInsightsController.AnalysisBundleWrapper exactBundle =
            findFirstMatchingStoredAnalysis(exactCandidates, sourceContentDocumentId);
        if (exactBundle != null) {
            return exactBundle;
        }

        List<Attachment> legacyCandidates = [
            SELECT Id, Name
            FROM Attachment
            WHERE ParentId IN :parentIds
              AND Name LIKE :legacyNotePattern
            ORDER BY LastModifiedDate DESC, CreatedDate DESC, Id DESC
            LIMIT :STORED_ANALYSIS_LEGACY_LIMIT
        ];

        return findFirstMatchingStoredAnalysis(legacyCandidates, sourceContentDocumentId);
    }

    private static GeminiFileInsightsController.AnalysisBundleWrapper findFirstMatchingStoredAnalysis(
        List<Attachment> candidates,
        Id sourceContentDocumentId
    ) {
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }

        Set<Id> hydratedAttachmentIds = new Set<Id>();
        for (Attachment candidate : candidates) {
            if (candidate == null || candidate.Id == null || hydratedAttachmentIds.contains(candidate.Id)) {
                continue;
            }
            hydratedAttachmentIds.add(candidate.Id);
            try {
                List<Attachment> hydratedRows = [
                    SELECT Id, Body, Name
                    FROM Attachment
                    WHERE Id = :candidate.Id
                    LIMIT 1
                ];
                if (hydratedRows.isEmpty()) {
                    continue;
                }

                String jsonString = hydratedRows[0].Body.toString();
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

    public static Attachment getStoredAnalysisAttachment(Id sourceContentDocumentId, Boolean includeBody) {
        ContentVersion sourceVersion = getLatestSourceVersion(sourceContentDocumentId);
        if (sourceVersion == null) {
            return null;
        }

        Set<Id> parentIds = getAnalysisParentIds(sourceContentDocumentId);
        String notePattern = buildNoteTitlePattern(sourceContentDocumentId);
        String legacyNotePattern = buildLegacyNoteTitlePattern(sourceContentDocumentId);

        if (includeBody == true) {
            List<Attachment> attachments = [
                SELECT Id, Body, Name, ParentId, CreatedDate, LastModifiedDate
                FROM Attachment
                WHERE ParentId IN :parentIds
                  AND (Name LIKE :notePattern OR Name LIKE :legacyNotePattern)
                ORDER BY LastModifiedDate DESC, CreatedDate DESC, Id DESC
                LIMIT 1
            ];
            return attachments.isEmpty() ? null : attachments[0];
        }

        List<Attachment> attachments = [
            SELECT Id, Name, ParentId, CreatedDate, LastModifiedDate
            FROM Attachment
            WHERE ParentId IN :parentIds
              AND (Name LIKE :notePattern OR Name LIKE :legacyNotePattern)
            ORDER BY LastModifiedDate DESC, CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        return attachments.isEmpty() ? null : attachments[0];
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
        Set<Id> parentIds = getAnalysisParentIds(sourceContentDocumentId);
        Id internalParentId = getInternalAnalysisParentId(sourceContentDocumentId);
        Id storageParentId = resolveWritableAttachmentParent(internalParentId, parentRecordId, sourceContentDocumentId);
        String notePattern = buildNoteTitlePattern(sourceContentDocumentId);
        String legacyNotePattern = buildLegacyNoteTitlePattern(sourceContentDocumentId);

        // Delete any existing attachments for this analysis to enforce single-record lifecycle
        List<Attachment> existing = [
            SELECT Id
            FROM Attachment
            WHERE ParentId IN :parentIds
              AND (Name LIKE :notePattern OR Name LIKE :legacyNotePattern)
        ];

        if (!existing.isEmpty()) {
            delete existing;
        }

        // Insert fresh attachment
        Attachment att = new Attachment();
        att.ParentId = storageParentId;
        att.Name = noteTitle;
        att.Body = noteBlob;
        att.ContentType = 'application/json';
        att.Description = 'Internal AI Analysis Store - auto-generated. Do not sync to Google Drive.';
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

    private static String buildNoteTitlePattern(Id sourceContentDocumentId) {
        return '% - AI Analysis Store [' + String.escapeSingleQuotes(String.valueOf(sourceContentDocumentId)) + ']';
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

    private static String buildLegacyNoteTitlePattern(Id sourceContentDocumentId) {
        return '% - AI Analysis Store [' + String.escapeSingleQuotes(String.valueOf(sourceContentDocumentId).left(8)) + ']';
    }

    private static Set<Id> getAnalysisParentIds(Id sourceContentDocumentId) {
        Set<Id> parentIds = new Set<Id>();
        Id internalParentId = getInternalAnalysisParentId(sourceContentDocumentId);
        if (internalParentId != null) {
            parentIds.add(internalParentId);
        }

        Id legacyParentId = getParentRecordId(sourceContentDocumentId);
        if (legacyParentId != null) {
            parentIds.add(legacyParentId);
        }

        parentIds.add(UserInfo.getUserId());
        return parentIds;
    }

    private static Id getInternalAnalysisParentId(Id sourceContentDocumentId) {
        ContentVersion sourceVersion = getLatestSourceVersion(sourceContentDocumentId);
        if (sourceVersion != null) {
            List<Document_Processing_Log__c> logs = [
                SELECT Id
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c = :String.valueOf(sourceVersion.Id)
                LIMIT 1
            ];
            if (!logs.isEmpty()) {
                return logs[0].Id;
            }
        }

        return UserInfo.getUserId();
    }

    private static Id resolveWritableAttachmentParent(Id internalParentId, Id parentRecordId, Id sourceContentDocumentId) {
        if (isWritableAttachmentParent(internalParentId)) {
            return internalParentId;
        }
        if (isWritableAttachmentParent(parentRecordId)) {
            return parentRecordId;
        }

        Id linkedParentId = getParentRecordId(sourceContentDocumentId);
        if (isWritableAttachmentParent(linkedParentId)) {
            return linkedParentId;
        }

        return null;
    }

    private static Boolean isWritableAttachmentParent(Id parentId) {
        if (parentId == null || String.valueOf(parentId).startsWith('005')) {
            return false;
        }
        return parentId.getSObjectType() != User.SObjectType;
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