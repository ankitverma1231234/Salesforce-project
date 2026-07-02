public with sharing class GeminiFileInsightsController {
    
    private static final List<String> SECTION_ORDER = new List<String>{
        'summary',
            'keyFindings',
            'medicationReview',
            'labVitals',
            'riskAssessment',
            'actionItems',
            'patientSummary',
            
            'chiefComplaint',
            'keySymptoms',
            'allergies',
            'currentMedications',
            'medicalHistory',
            'surgicalHistory',
            'familyHistory',
            'socialHistory',
            'physicalExam',
            'labs',
            'imaging',
            'assessment',
            'differentialDiagnoses',
            'treatmentPlan'
            };
                
                public class FileInfoWrapper {
                    @AuraEnabled public String title;
                    @AuraEnabled public String fileType;
                    @AuraEnabled public String size;
                    @AuraEnabled public String createdDate;
                    @AuraEnabled public String owner;
                }
    
    public class TagGroupWrapper {
        public String category;
        public List<String> tags;
    }
    
    public class KeyFieldWrapper {
        public String groupName;
        public String label;
        public String value;
    }
    
    public class PatientContextWrapper {
        @AuraEnabled public String patientName;
        @AuraEnabled public String patientAge;
        @AuraEnabled public String patientGender;
        @AuraEnabled public String organizationName;
    }
    
    public class AnalysisBundleWrapper {
        @AuraEnabled public String sourceDocumentId;
        @AuraEnabled public String sourceLatestVersionId;
        @AuraEnabled public String analysisDocumentId;
        @AuraEnabled public String analysisVersionId;
        @AuraEnabled public String analysisTitle;
        @AuraEnabled public String generatedOn;
        @AuraEnabled public String plainTextContext;
        @AuraEnabled public String pdfDocumentId;
        @AuraEnabled public String pdfVersionId;
        @AuraEnabled public String parentRecordId;
        @AuraEnabled public FileInfoWrapper fileInfo;
        @AuraEnabled public Map<String, String> sections;
        @AuraEnabled public List<TagGroupWrapper> tagGroups;
        @AuraEnabled public List<KeyFieldWrapper> keyFields;
    }
    
    public class SavedFileResult {
        public Id contentDocumentId;
        public Id contentVersionId;
        public String title;
    }

    public class GeminiFileInsightsException extends Exception {}

    private static Exception buildHandledException(String message) {
        if (System.isBatch()) {
            return new GeminiFileInsightsException(message);
        }
        return new AuraHandledException(message);
    }
    
    @AuraEnabled
    public static String getAnalysisBundle(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw buildHandledException('ContentDocument Id is required.');
        }
        
        // Try stored note first (persistent)
        AnalysisBundleWrapper stored = GeminiAnalysisNoteService.getStoredAnalysis(contentDocumentId);
        if (stored != null) {
            String storedJson = JSON.serialize(stored);
            // Re-populate cache for fast same-session access
            GeminiCacheManager.putAnalysis(contentDocumentId, storedJson);
            return storedJson;
        }
        
        // Fall back to platform cache
        String cached = GeminiCacheManager.getAnalysis(contentDocumentId);
        return cached;
    }
    
    @AuraEnabled
    public static String generateFullAnalysis(Id contentDocumentId, Boolean forceRegenerate, Boolean attachPdf) {
        return generateFullAnalysis(contentDocumentId, forceRegenerate, attachPdf, false);
    }
    
    public static String generateFullAnalysis(Id contentDocumentId, Boolean forceRegenerate, Boolean attachPdf, Boolean skipCaching) {
        if (contentDocumentId == null) {
            throw buildHandledException('ContentDocument Id is required.');
        }
        
        if (forceRegenerate == null) {
            forceRegenerate = false;
        }
        if (attachPdf == null) {
            attachPdf = false;
        }
        if (skipCaching == null) {
            skipCaching = false;
        }
        
        ContentVersion cv = [
            SELECT Id, ContentDocumentId, Title, FileType, ContentSize, CreatedDate, Owner.Name, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        
        // If not forcing, check stored note first
        if (!forceRegenerate) {
            AnalysisBundleWrapper existing = GeminiAnalysisNoteService.getStoredAnalysis(contentDocumentId);
            if (existing != null && existing.sourceLatestVersionId == String.valueOf(cv.Id)) {
                String existingJson = JSON.serialize(existing);
                if (!skipCaching) {
                    GeminiCacheManager.putAnalysis(contentDocumentId, existingJson);
                }
                return existingJson;
            }
        }
        
        String fileType = cv.FileType != null ? cv.FileType.toUpperCase() : '';
        String mimeType = resolveMimeType(fileType);
        String prompt;
        String rawResponse;
        
        if (mimeType != null) {
            prompt = buildStructuredAnalysisPrompt(cv.Title, null);
            rawResponse = callGeminiWithBlob(prompt, cv.VersionData, mimeType);
        } else {
            String fileContent = extractFileContent(cv);
            if (String.isBlank(fileContent)) {
                throw buildHandledException(
                    'Unable to extract this file type for structured AI analysis.'
                );
            }
            
            if (fileContent.length() > 30000) {
                fileContent = fileContent.substring(0, 30000) + '\n\n[Content truncated...]';
            }
            
            prompt = buildStructuredAnalysisPrompt(cv.Title, fileContent);
            rawResponse = callGemini(prompt, cv.FileType);
        }
        
        AnalysisBundleWrapper bundle = deserializeAnalysis(rawResponse);
        bundle.sourceDocumentId = String.valueOf(contentDocumentId);
        bundle.sourceLatestVersionId = String.valueOf(cv.Id);
        bundle.fileInfo = buildFileInfoWrapper(cv);
        bundle.analysisTitle = buildAnalysisTitle(cv.Title);
        bundle.generatedOn = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        
        Id parentId = getPrimaryLinkedEntityId(contentDocumentId);
        bundle.parentRecordId = String.valueOf(parentId);
        
        normalizeBundle(bundle);
        
        // Build plain text context for cheaper Q&A reuse
        bundle.plainTextContext = buildPlainTextContext(bundle);
        
        String analysisJson = JSON.serialize(bundle);
        if (!skipCaching) {
            GeminiCacheManager.putAnalysis(contentDocumentId, analysisJson);
            GeminiCacheManager.putSummary(contentDocumentId, bundle.sections.get('summary'));
        }
        
        // Persist analysis Attachment (committed before any PDF render)
        Id analysisAttachmentId = GeminiAnalysisNoteService.upsertAnalysisNote(contentDocumentId, parentId, bundle);

        // Optionally generate and attach PDF
        if (attachPdf == true) {
            SavedFileResult saved = upsertAnalysisPdfToParent(contentDocumentId, bundle.analysisTitle, parentId, analysisAttachmentId, bundle);
            bundle.pdfDocumentId = String.valueOf(saved.contentDocumentId);
            bundle.pdfVersionId = String.valueOf(saved.contentVersionId);
            bundle.analysisDocumentId = String.valueOf(saved.contentDocumentId);
            bundle.analysisVersionId = String.valueOf(saved.contentVersionId);

            analysisJson = JSON.serialize(bundle);
            if (!skipCaching) {
                GeminiCacheManager.putAnalysis(contentDocumentId, analysisJson);
            }
            if (analysisAttachmentId != null) {
                GeminiAnalysisNoteService.updateAnalysisNoteBody(analysisAttachmentId, bundle);
            } else {
                GeminiAnalysisNoteService.upsertAnalysisNote(contentDocumentId, parentId, bundle);
            }
        }
        
        return analysisJson;
    }
    
    @AuraEnabled
    public static String generateAndDownloadPdf(Id contentDocumentId, Id parentRecordId) {
        if (contentDocumentId == null) {
            throw buildHandledException('ContentDocument Id is required.');
        }
        
        // Try cache, then note, then generate
        String cached = GeminiCacheManager.getAnalysis(contentDocumentId);
        
        if (String.isBlank(cached)) {
            AnalysisBundleWrapper noteBundle = GeminiAnalysisNoteService.getStoredAnalysis(contentDocumentId);
            if (noteBundle != null) {
                cached = JSON.serialize(noteBundle);
                GeminiCacheManager.putAnalysis(contentDocumentId, cached);
            }
        }
        
        if (String.isBlank(cached)) {
            cached = generateFullAnalysis(contentDocumentId, false, false);
        }
        
        if (String.isBlank(cached)) {
            throw buildHandledException('Unable to generate AI analysis. Please try Refresh Analysis first.');
        }
        
        AnalysisBundleWrapper bundle =
            (AnalysisBundleWrapper) JSON.deserialize(cached, AnalysisBundleWrapper.class);
        
        if (String.isNotBlank(bundle.analysisVersionId)) {
            return bundle.analysisVersionId;
        }
        
        Id publishLocationId = parentRecordId != null
            ? parentRecordId
            : getPrimaryLinkedEntityId(contentDocumentId);

        // Commit analysis Attachment before PDF render so the VF page can read it by Id.
        Id analysisAttachmentId = GeminiAnalysisNoteService.upsertAnalysisNote(contentDocumentId, publishLocationId, bundle);

        SavedFileResult saved = upsertAnalysisPdfToParent(contentDocumentId, bundle.analysisTitle, publishLocationId, analysisAttachmentId, bundle);
        bundle.analysisDocumentId = String.valueOf(saved.contentDocumentId);
        bundle.analysisVersionId = String.valueOf(saved.contentVersionId);
        bundle.pdfDocumentId = String.valueOf(saved.contentDocumentId);
        bundle.pdfVersionId = String.valueOf(saved.contentVersionId);

        String updatedJson = JSON.serialize(bundle);
        GeminiCacheManager.putAnalysis(contentDocumentId, updatedJson);
        if (analysisAttachmentId != null) {
            GeminiAnalysisNoteService.updateAnalysisNoteBody(analysisAttachmentId, bundle);
        } else {
            GeminiAnalysisNoteService.upsertAnalysisNote(contentDocumentId, publishLocationId, bundle);
        }

        return String.valueOf(saved.contentVersionId);
    }
    
    
    private static SavedFileResult upsertAnalysisPdfToParent(Id sourceContentDocumentId, String analysisTitle, Id publishLocationId) {
        return upsertAnalysisPdfToParent(sourceContentDocumentId, analysisTitle, publishLocationId, null, null);
    }

    private static SavedFileResult upsertAnalysisPdfToParent(Id sourceContentDocumentId, String analysisTitle, Id publishLocationId, Id analysisAttachmentId) {
        // Bundle not supplied directly — try to hydrate it from the analysis Attachment
        // so the pre-flight content check can still run. Falls through with null on failure.
        AnalysisBundleWrapper hydrated = null;
        if (analysisAttachmentId != null) {
            try {
                List<Attachment> atts = [SELECT Body FROM Attachment WHERE Id = :analysisAttachmentId LIMIT 1];
                if (!atts.isEmpty() && atts[0].Body != null) {
                    hydrated = (AnalysisBundleWrapper) JSON.deserialize(atts[0].Body.toString(), AnalysisBundleWrapper.class);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Failed to hydrate bundle from Attachment for content check: ' + e.getMessage());
            }
        }
        return upsertAnalysisPdfToParent(sourceContentDocumentId, analysisTitle, publishLocationId, analysisAttachmentId, hydrated);
    }

    private static SavedFileResult upsertAnalysisPdfToParent(Id sourceContentDocumentId, String analysisTitle, Id publishLocationId, Id analysisAttachmentId, AnalysisBundleWrapper bundle) {
        // Pre-flight: if the bundle has no renderable content, the VF page would emit
        // its empty state ("No AI analysis data was available..."). Don't waste a
        // ContentVersion insert on an empty PDF — flag the source file as
        // not-AI-generated so the retry mechanism picks it up, and bail out.
        if (!bundleHasRenderableContent(bundle)) {
            markSourceAiSummaryFlag(sourceContentDocumentId, false);
            throw buildHandledException('AI data capture failed: analysis content was empty at PDF generation. Source file marked for retry.');
        }

        PageReference pageRef = Page.GeminiFileInsightsPdf;
        pageRef.getParameters().put('contentDocumentId', String.valueOf(sourceContentDocumentId));
        if (analysisAttachmentId != null) {
            // Direct-by-Id handoff: VF controller reads the analysis JSON from this
            // Attachment in a single SOQL, bypassing platform cache and any
            // title/parent re-derivation in the separate getContentAsPDF() context.
            pageRef.getParameters().put('analysisAttachmentId', String.valueOf(analysisAttachmentId));
        }

        Blob pdfBlob = Test.isRunningTest() ? Blob.valueOf('Test PDF') : pageRef.getContentAsPDF();
        
        // Delete any existing AI Summary ContentDocument(s) to enforce single-file lifecycle
        List<ContentDocumentLink> existingLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :publishLocationId
            AND ContentDocument.Title = :analysisTitle
            And  ContentDocumentId = :sourceContentDocumentId
        ];
        
        if (!existingLinks.isEmpty()) {
            Set<Id> docIdsToDelete = new Set<Id>();
            for (ContentDocumentLink cdl : existingLinks) {
                docIdsToDelete.add(cdl.ContentDocumentId);
            }
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docIdsToDelete];
        }
        
        // Fetch Service_Date_Time__c and Send_File_to_Portal__c from the source file
        List<ContentVersion> sourceVersions = [
            SELECT Service_Date_Time__c, Send_File_to_Portal__c
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
        newVersion.FirstPublishLocationId = publishLocationId;
        newVersion.Source_Type__c = 'AI';
        
        if (!sourceVersions.isEmpty()) {
            newVersion.Service_Date_Time__c = sourceVersions[0].Service_Date_Time__c;
            newVersion.Send_File_to_Portal__c = sourceVersions[0].Send_File_to_Portal__c;
        }
        
        insert newVersion;
        List<ContentVersion> conVer = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :sourceContentDocumentId
            
            LIMIT 1
        ];
        
        if (!conVer.isEmpty()) {
            ContentVersion summaryFlagUpdate = new ContentVersion(
                Id = conVer[0].Id,
                Is_AI_Summary_Generated__c = true
            );
            update summaryFlagUpdate;
        }
        
        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :newVersion.Id
            LIMIT 1
        ];
        
        SavedFileResult result = new SavedFileResult();
        result.contentVersionId = insertedVersion.Id;
        result.contentDocumentId = insertedVersion.ContentDocumentId;
        result.title = analysisTitle;
        return result;
    }

    // Mirrors the empty-state logic in GeminiFileInsightsPdfController: a bundle
    // is "renderable" if at least one section has non-blank, non-placeholder HTML
    // OR there is at least one keyField with a real value. Anything else would
    // render as the VF page's empty state.
    public static Boolean bundleHasRenderableContent(AnalysisBundleWrapper bundle) {
        if (bundle == null) return false;

        if (bundle.sections != null) {
            for (String html : bundle.sections.values()) {
                if (String.isBlank(html)) continue;
                String stripped = html.replaceAll('<[^>]*>', '').trim().toLowerCase();
                if (String.isBlank(stripped)) continue;
                if (stripped == 'no information available for this section.'
                    || stripped == 'no information available.'
                    || stripped == 'not documented.'
                    || stripped == 'n/a'
                    || stripped == '-') {
                    continue;
                }
                return true;
            }
        }

        if (bundle.keyFields != null) {
            for (KeyFieldWrapper kf : bundle.keyFields) {
                if (String.isBlank(kf.value)) continue;
                String v = kf.value.trim();
                if (v == '-' || v.equalsIgnoreCase('Not stated') || v.equalsIgnoreCase('N/A')) continue;
                return true;
            }
        }

        return false;
    }

    // Flip Is_AI_Summary_Generated__c on the latest source ContentVersion. Setting
    // this to false is the signal the retry mechanism listens for. Setting it to
    // true after a successful PDF render is handled inline in upsertAnalysisPdfToParent.
    private static void markSourceAiSummaryFlag(Id sourceContentDocumentId, Boolean value) {
        if (sourceContentDocumentId == null) return;
        List<ContentVersion> versions = [
            SELECT Id FROM ContentVersion
            WHERE ContentDocumentId = :sourceContentDocumentId
              AND IsLatest = true
            LIMIT 1
        ];
        if (versions.isEmpty()) return;
        try {
            update new ContentVersion(Id = versions[0].Id, Is_AI_Summary_Generated__c = value);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to update Is_AI_Summary_Generated__c=' + value + ': ' + e.getMessage());
        }
    }


    @AuraEnabled(cacheable=true)
    public static Id getParentRecordId(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return null;
        }
        return getPrimaryLinkedEntityId(contentDocumentId);
    }
    
    @AuraEnabled
    public static String askQuestion(Id contentDocumentId, String question) {
        if (contentDocumentId == null) {
            throw buildHandledException('ContentDocument Id is required.');
        }
        if (String.isBlank(question)) {
            throw buildHandledException('Question is required.');
        }
        
        // Try stored note context first (saves tokens)
        AnalysisBundleWrapper stored = GeminiAnalysisNoteService.getStoredAnalysis(contentDocumentId);
        if (stored != null && !GeminiAnalysisNoteService.isAnalysisStale(contentDocumentId)
            && String.isNotBlank(stored.plainTextContext)) {
                
                String notePrompt =
                    'You are answering a follow-up question using stored AI notes extracted from a healthcare document. '
                    + 'Rely on the stored notes below. If a detail is not present, say it is not documented.\n\n'
                    + 'User Question: ' + question + '\n\n'
                    + 'Stored Notes:\n' + stored.plainTextContext;
                
                return callGemini(notePrompt, 'TXT');
            }
        
        // Fallback: use raw source file
        List<ContentVersion> versions = [
            SELECT Id, Title, FileType, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        
        if (versions.isEmpty()) {
            throw buildHandledException('File not found.');
        }
        
        ContentVersion cv = versions[0];
        String fileType = cv.FileType != null ? cv.FileType.toUpperCase() : '';
        String mimeType = resolveMimeType(fileType);
        
        String prompt =
            'You are a helpful document assistant. Based on the attached file, answer the user clearly, precisely, and concisely. '
            + 'Use short paragraphs or bullet points where helpful.\n\n'
            + 'File Name: ' + cv.Title + '\n'
            + 'User Question: ' + question;
        
        if (mimeType != null) {
            return callGeminiWithBlob(prompt, cv.VersionData, mimeType);
        }
        
        String fileContent = extractFileContent(cv);
        if (String.isBlank(fileContent)) {
            return 'Unable to extract content from this file type to answer questions.';
        }
        
        if (fileContent.length() > 30000) {
            fileContent = fileContent.substring(0, 30000) + '\n\n[Content truncated...]';
        }
        
        prompt += '\n\nDocument Content:\n' + fileContent;
        return callGemini(prompt, cv.FileType);
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFileInfo(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw buildHandledException('ContentDocument Id is required.');
        }
        
        List<ContentVersion> versions = [
            SELECT Id, Title, FileType, ContentSize, CreatedDate, Owner.Name, Is_AI_Summary_Generated__c
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        
        Map<String, String> info = new Map<String, String>();
        if (!versions.isEmpty()) {
            ContentVersion cv = versions[0];
            info.put('title', cv.Title);
            info.put('fileType', cv.FileType);
            info.put('size', formatFileSize(cv.ContentSize));
            info.put('createdDate', cv.CreatedDate.format('MMM dd, yyyy'));
            info.put('owner', cv.Owner.Name);
            info.put('isAiSummaryGenerated', String.valueOf(cv.Is_AI_Summary_Generated__c));
        }
        return info;
    }
    
    @AuraEnabled
    public static Map<String, Object> getAnalysisStatus(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw buildHandledException('ContentDocument Id is required.');
        }
        
        Map<String, Object> status = new Map<String, Object>();
        
        AnalysisBundleWrapper stored = GeminiAnalysisNoteService.getStoredAnalysis(contentDocumentId);
        Boolean hasStoredNote = (stored != null);
        status.put('hasStoredNote', hasStoredNote);
        
        if (hasStoredNote) {
            Boolean isStale = GeminiAnalysisNoteService.isAnalysisStale(contentDocumentId);
            status.put('isStale', isStale);
            status.put('hasPdf', String.isNotBlank(stored.pdfVersionId));
            status.put('pdfVersionId', stored.pdfVersionId);
            status.put('sourceLatestVersionId', stored.sourceLatestVersionId);
            status.put('storedGeneratedOn', stored.generatedOn);
        } else {
            status.put('isStale', true);
            status.put('hasPdf', false);
            status.put('pdfVersionId', null);
            status.put('sourceLatestVersionId', null);
            status.put('storedGeneratedOn', null);
        }
        
        return status;
    }
    
    @AuraEnabled(cacheable=true)
    public static PatientContextWrapper getPatientContext(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return null;
        }
        
        PatientContextWrapper ctx = new PatientContextWrapper();
        
        // Fetch Organization_Name__c from ContentVersion
        List<ContentVersion> versions = [
            SELECT Id, Organization_Name__c
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        
        if (!versions.isEmpty() && String.isNotBlank(versions[0].Organization_Name__c)) {
            ctx.organizationName = versions[0].Organization_Name__c;
        }
        
        // Fetch Account data from parent relationship
        Id parentId = getPrimaryLinkedEntityId(contentDocumentId);
        if (parentId != null && parentId.getSObjectType() == Account.SObjectType) {
            List<Account> accounts = [
                SELECT Name, Date_of_Birth__pc, PersonGenderIdentity
                FROM Account
                WHERE Id = :parentId
                LIMIT 1
            ];
            
            if (!accounts.isEmpty()) {
                Account acc = accounts[0];
                ctx.patientName = acc.Name;
                ctx.patientGender = acc.PersonGenderIdentity;
                
                if (acc.Date_of_Birth__pc != null) {
                    Date dob = acc.Date_of_Birth__pc;
                    Date today = Date.today();
                    Integer age = today.year() - dob.year();
                    if (today.month() < dob.month() ||
                        (today.month() == dob.month() && today.day() < dob.day())) {
                            age--;
                        }
                    ctx.patientAge = String.valueOf(age);
                }
            }
        }
        
        return ctx;
    }
    
    @AuraEnabled
    public static SavedFileResult syncAnalysisPdf(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw buildHandledException('ContentDocument Id is required.');
        }
        
        // Get analysis from note or cache
        String analysisJson = GeminiCacheManager.getAnalysis(contentDocumentId);
        AnalysisBundleWrapper bundle;
        
        if (String.isNotBlank(analysisJson)) {
            bundle = (AnalysisBundleWrapper) JSON.deserialize(analysisJson, AnalysisBundleWrapper.class);
        } else {
            bundle = GeminiAnalysisNoteService.getStoredAnalysis(contentDocumentId);
            if (bundle != null) {
                analysisJson = JSON.serialize(bundle);
            }
        }
        
        if (bundle == null) {
            throw buildHandledException('No saved AI analysis found. Please run analysis first.');
        }

        GeminiCacheManager.putAnalysis(contentDocumentId, analysisJson);

        Id parentId = String.isNotBlank(bundle.parentRecordId)
            ? Id.valueOf(bundle.parentRecordId)
            : getPrimaryLinkedEntityId(contentDocumentId);

        String pdfTitle = bundle.analysisTitle;
        if (String.isBlank(pdfTitle)) {
            ContentVersion cv = [
                SELECT Title FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true LIMIT 1
            ];
            pdfTitle = buildAnalysisTitle(cv.Title);
        }

        // Commit the analysis Attachment BEFORE invoking getContentAsPDF(). The VF
        // page renders in a separate Apex transaction, so anything not persisted
        // (in-memory state, uncommitted DML) is invisible there. The returned
        // Attachment Id is forwarded to the VF controller for a direct-by-Id read.
        Id analysisAttachmentId = GeminiAnalysisNoteService.upsertAnalysisNote(contentDocumentId, parentId, bundle);

        SavedFileResult saved = upsertAnalysisPdfToParent(contentDocumentId, pdfTitle, parentId, analysisAttachmentId, bundle);

        bundle.pdfDocumentId = String.valueOf(saved.contentDocumentId);
        bundle.pdfVersionId = String.valueOf(saved.contentVersionId);
        bundle.analysisDocumentId = String.valueOf(saved.contentDocumentId);
        bundle.analysisVersionId = String.valueOf(saved.contentVersionId);

        String updatedJson = JSON.serialize(bundle);
        GeminiCacheManager.putAnalysis(contentDocumentId, updatedJson);
        // Field-only update on the same Attachment (no delete/insert) so the Id we
        // already handed to the VF page remains valid and we avoid extra DML.
        if (analysisAttachmentId != null) {
            GeminiAnalysisNoteService.updateAnalysisNoteBody(analysisAttachmentId, bundle);
        } else {
            GeminiAnalysisNoteService.upsertAnalysisNote(contentDocumentId, parentId, bundle);
        }

        return saved;
    }
    
    private static String buildPlainTextContext(AnalysisBundleWrapper bundle) {
        List<String> parts = new List<String>();
        
        if (bundle.fileInfo != null && String.isNotBlank(bundle.fileInfo.title)) {
            parts.add('File: ' + bundle.fileInfo.title);
        }
        
        if (bundle.sections != null) {
            Map<String, String> sectionLabels = new Map<String, String>{
                'summary' => 'Summary',
                    'keyFindings' => 'Key Findings',
                    'medicationReview' => 'Medication Review',
                    'labVitals' => 'Lab And Vitals',
                    'riskAssessment' => 'Risk Assessment',
                    'actionItems' => 'Action Items',
                    'patientSummary' => 'Patient Summary'
                    };
                        
                        for (String sectionKey : SECTION_ORDER) {
                            if (bundle.sections.containsKey(sectionKey)) {
                                String html = bundle.sections.get(sectionKey);
                                String plainText = stripHtml(html);
                                if (String.isNotBlank(plainText)
                                    && plainText != 'No information available for this section.'
                                    && plainText != 'No information available.'
                                    && plainText != 'Not documented.') {
                                        String label = sectionLabels.containsKey(sectionKey) ? sectionLabels.get(sectionKey) : sectionKey;
                                        parts.add(label + ': ' + plainText);
                                    }
                            }
                        }
        }
        
        if (bundle.keyFields != null && !bundle.keyFields.isEmpty()) {
            List<String> keyFieldParts = new List<String>();
            for (KeyFieldWrapper item : bundle.keyFields) {
                if (String.isNotBlank(item.value) && item.value != 'Not stated') {
                    keyFieldParts.add(item.groupName + ' - ' + item.label + ': ' + item.value);
                }
            }
            if (!keyFieldParts.isEmpty()) {
                parts.add('Key Fields: ' + String.join(keyFieldParts, ' | '));
            }
        }
        
        String result = String.join(parts, '\n\n');
        if (result.length() > 30000) {
            result = result.substring(0, 30000) + '\n[Truncated]';
        }
        return result;
    }
    
    private static String stripHtml(String html) {
        if (String.isBlank(html)) return '';
        String text = html.replaceAll('<br\\s*/?>', '\n');
        text = text.replaceAll('</p>', '\n');
        text = text.replaceAll('</li>', '\n');
        text = text.replaceAll('</tr>', '\n');
        text = text.replaceAll('<[^>]*>', '');
        text = text.replaceAll('&amp;', '&');
        text = text.replaceAll('&lt;', '<');
        text = text.replaceAll('&gt;', '>');
        text = text.replaceAll('&nbsp;', ' ');
        text = text.replaceAll('\\s+\\n', '\n');
        text = text.replaceAll('\\n{3,}', '\n\n');
        return text.trim();
    }
    
    private static FileInfoWrapper buildFileInfoWrapper(ContentVersion cv) {
        FileInfoWrapper info = new FileInfoWrapper();
        info.title = cv.Title;
        info.fileType = cv.FileType;
        info.size = formatFileSize(cv.ContentSize);
        info.createdDate = cv.CreatedDate.format('MMM dd, yyyy');
        info.owner = cv.Owner.Name;
        return info;
    }
    
    private static AnalysisBundleWrapper deserializeAnalysis(String rawResponse) {
        String cleaned = cleanupJson(rawResponse);
        
        // Attempt 1: standard deserialize
        try {
            return (AnalysisBundleWrapper) JSON.deserialize(cleaned, AnalysisBundleWrapper.class);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'First JSON parse failed: ' + e.getMessage());
        }
        
        // Attempt 2: strip control characters and retry
        try {
            String sanitized = cleaned.replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', '');
            return (AnalysisBundleWrapper) JSON.deserialize(sanitized, AnalysisBundleWrapper.class);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Second JSON parse failed: ' + e.getMessage());
        }
        
        // Attempt 3: try JSONParser for manual extraction
        try {
            Map<String, Object> rawMap = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            AnalysisBundleWrapper manual = new AnalysisBundleWrapper();
            manual.sections = new Map<String, String>();
            manual.tagGroups = new List<TagGroupWrapper>();
            manual.keyFields = new List<KeyFieldWrapper>();
            
            if (rawMap.containsKey('sections')) {
                Map<String, Object> sectionsMap = (Map<String, Object>) rawMap.get('sections');
                for (String key : sectionsMap.keySet()) {
                    Object val = sectionsMap.get(key);
                    manual.sections.put(key, val != null ? String.valueOf(val) : '');
                }
            }
            
            if (rawMap.containsKey('tagGroups')) {
                List<Object> tgList = (List<Object>) rawMap.get('tagGroups');
                for (Object tgObj : tgList) {
                    Map<String, Object> tgMap = (Map<String, Object>) tgObj;
                    TagGroupWrapper tg = new TagGroupWrapper();
                    tg.category = (String) tgMap.get('category');
                    tg.tags = new List<String>();
                    if (tgMap.containsKey('tags')) {
                        List<Object> tagsList = (List<Object>) tgMap.get('tags');
                        for (Object t : tagsList) {
                            tg.tags.add(String.valueOf(t));
                        }
                    }
                    manual.tagGroups.add(tg);
                }
            }
            
            if (rawMap.containsKey('keyFields')) {
                List<Object> kfList = (List<Object>) rawMap.get('keyFields');
                for (Object kfObj : kfList) {
                    Map<String, Object> kfMap = (Map<String, Object>) kfObj;
                    KeyFieldWrapper kf = new KeyFieldWrapper();
                    kf.groupName = (String) kfMap.get('groupName');
                    kf.label = (String) kfMap.get('label');
                    kf.value = (String) kfMap.get('value');
                    manual.keyFields.add(kf);
                }
            }
            
            return manual;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Manual JSON extraction failed: ' + e.getMessage());
        }
        
        // Final fallback: extract summary text if possible, never dump raw JSON
        AnalysisBundleWrapper fallback = new AnalysisBundleWrapper();
        fallback.sections = new Map<String, String>();
        fallback.tagGroups = new List<TagGroupWrapper>();
        fallback.keyFields = new List<KeyFieldWrapper>();
        
        String extractedSummary = extractSummaryFromRaw(rawResponse);
        fallback.sections.put('summary', extractedSummary);
        
        return fallback;
    }
    
    
    private static String extractSummaryFromRaw(String rawResponse) {
        if (String.isBlank(rawResponse)) {
            return '<p>AI analysis could not be parsed. Please try refreshing.</p>';
        }
        
        // Try to find the summary value between "summary": " and the next section key
        try {
            String searchKey = '"summary"';
            Integer keyIndex = rawResponse.indexOf(searchKey);
            if (keyIndex >= 0) {
                // Find the colon after "summary"
                Integer colonIndex = rawResponse.indexOf(':', keyIndex + searchKey.length());
                if (colonIndex >= 0) {
                    // Find opening quote of value
                    Integer openQuote = rawResponse.indexOf('"', colonIndex + 1);
                    if (openQuote >= 0) {
                        // Find closing quote â€” look for ", " followed by a known section key or end of sections
                        String remaining = rawResponse.substring(openQuote + 1);
                        // Find the end by looking for next section key pattern
                        List<String> nextKeys = new List<String>{
                            '"keyFindings"', '"medicationReview"', '"labVitals"',
                                '"riskAssessment"', '"actionItems"', '"patientSummary"'
                                };
                                    
                                    Integer endPos = remaining.length();
                        for (String nextKey : nextKeys) {
                            Integer nkPos = remaining.indexOf(nextKey);
                            if (nkPos > 0 && nkPos < endPos) {
                                endPos = nkPos;
                            }
                        }
                        
                        String summaryValue = remaining.substring(0, endPos).trim();
                        // Clean up trailing comma and quote
                        if (summaryValue.endsWith(',')) {
                            summaryValue = summaryValue.substring(0, summaryValue.length() - 1).trim();
                        }
                        if (summaryValue.endsWith('"')) {
                            summaryValue = summaryValue.substring(0, summaryValue.length() - 1);
                        }
                        
                        // Unescape basic JSON escapes
                        summaryValue = summaryValue.replace('\\"', '"');
                        summaryValue = summaryValue.replace('\\n', '\n');
                        summaryValue = summaryValue.replace('\\/', '/');
                        
                        if (String.isNotBlank(summaryValue)) {
                            // If it already has HTML tags, return as-is; otherwise wrap in <p>
                            if (summaryValue.containsIgnoreCase('<p>') || summaryValue.containsIgnoreCase('<ul>')) {
                                return summaryValue;
                            }
                            return '<p>' + summaryValue + '</p>';
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Summary extraction failed: ' + e.getMessage());
        }
        
        return '<p>AI analysis was generated but could not be displayed. Please click Refresh Analysis to try again.</p>';
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    private static void normalizeBundle(AnalysisBundleWrapper bundle) {
        if (bundle.sections == null) {
            bundle.sections = new Map<String, String>();
        }
        
        for (String sectionName : SECTION_ORDER) {
            if (!bundle.sections.containsKey(sectionName) || String.isBlank(bundle.sections.get(sectionName))) {
                bundle.sections.put(sectionName, '<p>No information available for this section.</p>');
            } else {
                bundle.sections.put(sectionName, normalizeHtml(bundle.sections.get(sectionName)));
            }
        }
        
        if (bundle.tagGroups == null) {
            bundle.tagGroups = new List<TagGroupWrapper>();
        }
        
        for (TagGroupWrapper tagGroup : bundle.tagGroups) {
            if (tagGroup.tags == null) {
                tagGroup.tags = new List<String>();
            }
        }
        
        if (bundle.keyFields == null) {
            bundle.keyFields = new List<KeyFieldWrapper>();
        }
        
        for (KeyFieldWrapper keyField : bundle.keyFields) {
            if (String.isBlank(keyField.groupName)) {
                keyField.groupName = 'Extracted Fields';
            }
            if (String.isBlank(keyField.label)) {
                keyField.label = 'Field';
            }
            if (String.isBlank(keyField.value)) {
                keyField.value = 'Not stated';
            }
        }
    }
    
    private static SavedFileResult upsertAnalysisPdf(Id sourceContentDocumentId, String analysisTitle) {
        PageReference pageRef = Page.GeminiFileInsightsPdf;
        pageRef.getParameters().put('contentDocumentId', String.valueOf(sourceContentDocumentId));
        
        Blob pdfBlob = Test.isRunningTest() ? Blob.valueOf('Test PDF') : pageRef.getContentAsPDF();
        
        Id publishLocationId = getPrimaryLinkedEntityId(sourceContentDocumentId);
        
        // Delete any existing AI Summary ContentDocument(s) to enforce single-file lifecycle
        List<ContentDocumentLink> existingLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :publishLocationId
            AND ContentDocument.Title = :analysisTitle
        ];
        
        if (!existingLinks.isEmpty()) {
            Set<Id> docIdsToDelete = new Set<Id>();
            for (ContentDocumentLink cdl : existingLinks) {
                docIdsToDelete.add(cdl.ContentDocumentId);
            }
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docIdsToDelete];
        }
        
        // Fetch Service_Date_Time__c and Send_File_to_Portal__c from the source file
        List<ContentVersion> sourceVersions = [
            SELECT Service_Date_Time__c, Send_File_to_Portal__c
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
        newVersion.FirstPublishLocationId = publishLocationId;
        newVersion.Source_Type__c = 'AI';
        
        if (!sourceVersions.isEmpty()) {
            newVersion.Service_Date_Time__c = sourceVersions[0].Service_Date_Time__c;
            newVersion.Send_File_to_Portal__c = sourceVersions[0].Send_File_to_Portal__c;
        }
        
        insert newVersion;
        
        List<ContentVersion> conVer = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :sourceContentDocumentId
            
            LIMIT 1
        ];
        
        if (!conVer.isEmpty()) {
            ContentVersion summaryFlagUpdate = new ContentVersion(
                Id = conVer[0].Id,
                Is_AI_Summary_Generated__c = true
            );
            update summaryFlagUpdate;
        }
        
        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :newVersion.Id
            LIMIT 1
        ];
        
        SavedFileResult result = new SavedFileResult();
        result.contentVersionId = insertedVersion.Id;
        result.contentDocumentId = insertedVersion.ContentDocumentId;
        result.title = analysisTitle;
        return result;
    }
    
    private static Id getPrimaryLinkedEntityId(Id contentDocumentId) {
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
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
    
    private static String buildAnalysisTitle(String sourceTitle) {
        String title = sourceTitle + ' - AI Generated Summary';
        if (title.length() > 220) {
            title = title.substring(0, 220);
        }
        return title;
    }
    
    private static String cleanupJson(String rawResponse) {
        if (String.isBlank(rawResponse)) {
            return '{}';
        }
        
        String cleaned = rawResponse.trim();
        
        // Remove markdown code fences
        cleaned = cleaned.replace('```json', '');
        cleaned = cleaned.replace('```', '');
        
        // Strip control characters that break JSON parsing (keep \n \r \t)
        cleaned = cleaned.replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', '');
        
        // Find the first { and the matching last }
        Integer firstBrace = cleaned.indexOf('{');
        Integer lastBrace = cleaned.lastIndexOf('}');
        
        if (firstBrace >= 0 && lastBrace > firstBrace) {
            cleaned = cleaned.substring(firstBrace, lastBrace + 1);
        }
        
        return cleaned.trim();
    }
    
    private static String normalizeHtml(String html) {
        if (String.isBlank(html)) {
            return '<p>No information available.</p>';
        }
        
        String normalized = html;
        normalized = normalized.replaceAll('(?i)<b>', '<strong>');
        normalized = normalized.replaceAll('(?i)</b>', '</strong>');
        normalized = normalized.replaceAll('(?i)<i>', '<em>');
        normalized = normalized.replaceAll('(?i)</i>', '</em>');
        normalized = normalized.replaceAll('(?is)<script.*?>.*?</script>', '');
        normalized = normalized.replaceAll('(?is)<style.*?>.*?</style>', '');
        normalized = normalized.replaceAll('(?i)javascript:', '');
        return normalized;
    }
    
    private static String escapeHtml(String text) {
        if (text == null) {
            return '';
        }
        return text.escapeHtml4();
    }
    
    private static String resolveMimeType(String fileType) {
        if (String.isBlank(fileType)) {
            return null;
        }
        
        String normalized = fileType.toUpperCase();
        
        if (normalized == 'PDF') return 'application/pdf';
        if (normalized == 'PNG') return 'image/png';
        if (normalized == 'JPG' || normalized == 'JPEG') return 'image/jpeg';
        if (normalized == 'GIF') return 'image/gif';
        if (normalized == 'WEBP') return 'image/webp';
        if (normalized == 'BMP') return 'image/bmp';
        if (normalized == 'TIFF' || normalized == 'TIF') return 'image/tiff';
        
        return null;
    }
    
    private static String extractFileContent(ContentVersion cv) {
        if (cv.VersionData == null) {
            return null;
        }
        
        String fileType = cv.FileType != null ? cv.FileType.toUpperCase() : '';
        
        Set<String> textTypes = new Set<String>{
            'TEXT', 'TXT', 'CSV', 'XML', 'HTML', 'JSON', 'RTF', 'LOG', 'MD'
                };
                    
                    if (textTypes.contains(fileType)) {
                        return cv.VersionData.toString();
                    }
        
        Set<String> attemptTypes = new Set<String>{ 'DOC', 'DOCX', 'SNOTE' };
            if (attemptTypes.contains(fileType)) {
                try {
                    return cv.VersionData.toString();
                } catch (Exception e) {
                    return null;
                }
            }
        
        return null;
    }
    
    private static String buildStructuredAnalysisPrompt(String fileName, String fileContent) {
        String prompt =
            'You are an expert healthcare document analyst specializing in neurology and clinical records.\n'
            + 'Analyze the attached medical document and respond ONLY with valid JSON.\n'
            + 'No markdown fences. No explanation. No prose outside JSON.\n\n'
            + 'Return this exact JSON shape:\n'
            + '{\n'
            + '  "sections": {\n'
            + '    "chiefComplaint": "<ul><li>...</li></ul>",\n'
            + '    "keySymptoms": "<ul><li>...</li></ul>",\n'
            + '    "allergies": "<p>...</p>",\n'
            + '    "currentMedications": "<ol><li>...</li></ol>",\n'
            + '    "medicalHistory": "<ol><li>...</li></ol>",\n'
            + '    "surgicalHistory": "<ul><li>...</li></ul>",\n'
            + '    "familyHistory": "<p>...</p>",\n'
            + '    "socialHistory": "<ul><li>...</li></ul>",\n'
            + '    "physicalExam": "<ul><li>...</li></ul>",\n'
            + '    "labs": "<p>...</p>",\n'
            + '    "imaging": "<p>...</p>",\n'
            + '    "assessment": "<ol><li>...</li></ol>",\n'
            + '    "differentialDiagnoses": "<ul><li>...</li></ul>",\n'
            + '    "treatmentPlan": "<ol><li>...</li></ol>"\n'
            + '  },\n'
            + '  "tagGroups": [\n'
            + '    { "category": "Clinical Information", "tags": ["...", "..."] },\n'
            + '    { "category": "Medications & Allergies", "tags": ["...", "..."] },\n'
            + '    { "category": "Preventive & Social Health", "tags": ["...", "..."] },\n'
            + '    { "category": "Encounters & Care", "tags": ["...", "..."] },\n'
            + '    { "category": "Insurance", "tags": ["...", "..."] },\n'
            + '    { "category": "Document Metadata", "tags": ["...", "..."] }\n'
            + '  ],\n'
            + '  "keyFields": [\n'
            + '    { "groupName": "Patient Demographics", "label": "Patient Name", "value": "..." },\n'
            + '    { "groupName": "Patient Demographics", "label": "Date of Birth", "value": "..." },\n'
            + '    { "groupName": "Encounter Details", "label": "Consulting Clinician", "value": "..." },\n'
            + '    { "groupName": "Encounter Details", "label": "Location", "value": "..." },\n'
            + '    { "groupName": "Encounter Details", "label": "Note Date", "value": "..." }\n'
            + '  ],\n'
            + '  "plainTextContext": "Concise plain-text version of all important sections for Q&A reuse. Include chief complaint, key symptoms, medications with dosages, diagnoses, differential diagnoses, treatment plan, and follow-up instructions. Do not include any blank or placeholder sections."\n'
            + '}\n\n'
            + 'Rules:\n'
            + '1. Use only simple HTML tags inside sections: p, ul, ol, li, strong, em, h3, table, thead, tbody, tr, th, td, br, mark.\n'
            + '2. Do not use b or i tags.\n'
            + '3. Extract actual values in keyFields only when they are explicitly present in the document.\n'
            + '4. For tagGroups, extract the actual patient-specific clinical terms from the document exactly as they appear (e.g., specific drug names with dosages, precise diagnoses, exact facility names). Do not use generic placeholders.\n'
            + '5. For all sections and fields, return the actual patient-specific value, not the section label (do not return "Chief Complaint", "HPI", "ROS", etc.).\n'
            + '6. For labs and imaging: if no data is present, return <p>Not documented.</p> as the value.\n'
            + '7. For familyHistory and surgicalHistory: if no data is present, return <p>Not documented.</p> as the value.\n'
            + '8. In currentMedications, preserve drug name, dosage, route, frequency, and purpose when explicitly stated. Flag NEW prescriptions with <mark>NEW</mark>.\n'
            + '9. In medicalHistory, include ICD codes in parentheses when present, e.g. Cervical radiculopathy (M54.12).\n'
            + '10. In physicalExam, include vitals as a sub-list when present (BP, HR, RR, Height, Weight, BMI), followed by system-level findings.\n'
            + '11. In treatmentPlan, include any ordered tests, new prescriptions, medication continuations, and follow-up timing.\n'
            + '12. Keep tagGroups based on what is actually documented — skip a group if its content is entirely absent.\n'
            + '13. The plainTextContext must never include empty placeholder sections.\n\n'
            + 'File Name: ' + fileName;
        
        if (String.isNotBlank(fileContent)) {
            prompt += '\n\nDocument Content:\n' + fileContent;
        } else {
            prompt += '\n\nThe source file is attached inline.';
        }
        
        return prompt;
    }
    
    private static String callGemini(String prompt, String fileType) {
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.API_Key__c)) {
            throw buildHandledException('Gemini AI is not configured. Please set up Gemini AI Settings.');
        }
        if (settings == null || String.isBlank(settings.Endpoint__c)) {
            throw buildHandledException('Gemini AI is not configured. Please set up Gemini AI Settings.');
        }
        
        
        List<Map<String, Object>> parts = new List<Map<String, Object>>();
        parts.add(new Map<String, Object>{ 'text' => prompt });
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'contents' => new List<Object>{
                new Map<String, Object>{ 'parts' => parts }
            },
                'generationConfig' => new Map<String, Object>{
                    'temperature' => 0.2,
                        'maxOutputTokens' => 4096,
                        'candidateCount' => 1
                        }
        };
            
            HttpRequest req = new HttpRequest();
        req.setEndpoint(settings.Endpoint__c + '?key=' + EncodingUtil.urlEncode(settings.API_Key__c, 'UTF-8'));
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(requestBody));
        req.setTimeout(120000);
        
        HttpResponse res = new Http().send(req);
        
        if (res.getStatusCode() == 200) {
            return parseResponse(res.getBody());
        }
        
        System.debug(LoggingLevel.ERROR, 'Gemini API error: ' + res.getStatusCode() + ' - ' + res.getBody());
        throw buildHandledException('Gemini API returned an error (Status: ' + res.getStatusCode() + '). Please try again.');
    }
    
    private static String callGeminiWithBlob(String prompt, Blob fileBlob, String mimeType) {
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.API_Key__c)) {
            throw buildHandledException('Gemini AI is not configured. Please set up Gemini AI Settings.');
        }
        if (settings == null || String.isBlank(settings.Endpoint__c)) {
            throw buildHandledException('Gemini AI is not configured. Please set up Gemini AI Settings.');
        }
        
        
        
        List<Map<String, Object>> parts = new List<Map<String, Object>>();
        parts.add(new Map<String, Object>{ 'text' => prompt });
        
        if (fileBlob != null) {
            Map<String, Object> inlineData = new Map<String, Object>{
                'mime_type' => mimeType,
                    'data' => EncodingUtil.base64Encode(fileBlob)
                    };
                        parts.add(new Map<String, Object>{ 'inline_data' => inlineData });
        }
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'contents' => new List<Object>{
                new Map<String, Object>{ 'parts' => parts }
            },
                'generationConfig' => new Map<String, Object>{
                    'temperature' => 0.2,
                        'maxOutputTokens' => 4096,
                        'candidateCount' => 1
                        }
        };
            
            HttpRequest req = new HttpRequest();
        req.setEndpoint(settings.Endpoint__c + '?key=' + EncodingUtil.urlEncode(settings.API_Key__c, 'UTF-8'));
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(requestBody));
        req.setTimeout(120000);
        
        HttpResponse res = new Http().send(req);
        
        if (res.getStatusCode() == 200) {
            return parseResponse(res.getBody());
        }
        
        System.debug(LoggingLevel.ERROR, 'Gemini API error: ' + res.getStatusCode() + ' - ' + res.getBody());
        throw buildHandledException('Gemini API returned an error (Status: ' + res.getStatusCode() + '). Please try again.');
    }
    
    private static String parseResponse(String responseBody) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> candidates = (List<Object>) responseMap.get('candidates');
        
        if (candidates == null || candidates.isEmpty()) {
            return 'No response generated by Gemini.';
        }
        
        Map<String, Object> candidate = (Map<String, Object>) candidates[0];
        Object contentObj = candidate.get('content');
        
        if (contentObj != null && contentObj instanceof Map<String, Object>) {
            Map<String, Object> contentMap = (Map<String, Object>) contentObj;
            
            if (contentMap.containsKey('text') && contentMap.get('text') != null) {
                return (String) contentMap.get('text');
            }
            
            Object partsObj = contentMap.get('parts');
            if (partsObj instanceof List<Object>) {
                List<Object> parts = (List<Object>) partsObj;
                if (!parts.isEmpty()) {
                    Object partObj = parts[0];
                    if (partObj instanceof Map<String, Object>) {
                        Map<String, Object> part = (Map<String, Object>) partObj;
                        if (part.containsKey('text')) {
                            return (String) part.get('text');
                        }
                    }
                }
            }
        }
        
        return 'Unable to parse Gemini response.';
    }
    
    private static String formatFileSize(Long sizeInBytes) {
        if (sizeInBytes == null || sizeInBytes == 0) return '0 Bytes';
        if (sizeInBytes < 1024) return sizeInBytes + ' Bytes';
        if (sizeInBytes < 1048576) return Math.round(sizeInBytes / 1024.0) + ' KB';
        return (Decimal.valueOf(sizeInBytes) / 1048576).setScale(1) + ' MB';
    }
}