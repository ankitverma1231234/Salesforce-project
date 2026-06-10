public with sharing class FraFileStorageAiInsightsService {
    private static final String STATUS_READY = 'READY';
    private static final String STATUS_NO_CONTENT_DOCUMENT = 'NO_CONTENT_DOCUMENT';
    private static final String STATUS_NO_ATTACHMENT = 'NO_ATTACHMENT';
    private static final String STATUS_PARSE_ERROR = 'PARSE_ERROR';
    private static final String STATUS_ERROR = 'ERROR';

    public class InsightsResponse {
        @AuraEnabled public Boolean hasInsights;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public String fileStorageId;
        @AuraEnabled public String fileStorageName;
        @AuraEnabled public String uploadedDrive;
        @AuraEnabled public String parentRecordId;
        @AuraEnabled public String originalFileName;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String attachmentId;
        @AuraEnabled public String attachmentName;
        @AuraEnabled public String analysisTitle;
        @AuraEnabled public String generatedOn;
        @AuraEnabled public String plainTextContext;
        @AuraEnabled public FileInfoWrapper fileInfo;
        @AuraEnabled public PatientContextWrapper patientContext;
        @AuraEnabled public Map<String, String> sections;
        @AuraEnabled public List<TagGroupWrapper> tagGroups;
        @AuraEnabled public List<KeyFieldWrapper> keyFields;
    }

    public class FileInfoWrapper {
        @AuraEnabled public String title;
        @AuraEnabled public String fileType;
        @AuraEnabled public String size;
        @AuraEnabled public String createdDate;
        @AuraEnabled public String owner;
    }

    public class PatientContextWrapper {
        @AuraEnabled public String patientName;
        @AuraEnabled public String patientAge;
        @AuraEnabled public String patientGender;
        @AuraEnabled public String organizationName;
    }

    public class TagGroupWrapper {
        @AuraEnabled public String category;
        @AuraEnabled public List<String> tags;
    }

    public class KeyFieldWrapper {
        @AuraEnabled public String groupName;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    private class ResolutionContext {
        fra__File_Storage__c fileStorage;
        String originalFileName;
        ContentVersion contentVersion;
        Attachment attachment;
        InsightsResponse response;
    }

    @AuraEnabled(cacheable=true)
    public static InsightsResponse getInsights(Id fileStorageId) {
        System.debug(LoggingLevel.DEBUG, 'FraFileStorageAiInsightsService.getInsights started. fileStorageId=' + fileStorageId);

        InsightsResponse response = newBaseResponse();
        if (fileStorageId == null) {
            response.status = STATUS_ERROR;
            response.message = 'File Storage record is required.';
            return response;
        }

        try {
            requireReadAccess();
            ResolutionContext context = resolveContext(fileStorageId, true);
            response = context.response;

            if (context.fileStorage != null) {
                hydrateFileStorageResponse(response, context.fileStorage, context.originalFileName);
            }
            if (context.contentVersion != null) {
                response.contentDocumentId = String.valueOf(context.contentVersion.ContentDocumentId);
                response.contentVersionId = String.valueOf(context.contentVersion.Id);
                response.fileInfo = buildFileInfo(context.contentVersion);
                response.patientContext = buildPatientContext(context.contentVersion, response.parentRecordId);
            }
            if (context.attachment != null) {
                response.attachmentId = String.valueOf(context.attachment.Id);
                response.attachmentName = context.attachment.Name;
                parseAttachmentBody(context.attachment, response);
                if (response.status == STATUS_READY) {
                    System.debug(LoggingLevel.DEBUG, 'AI insights loaded from Attachment. attachmentId=' + context.attachment.Id);
                }
            }
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'FraFileStorageAiInsightsService.getInsights failed: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            response.status = STATUS_ERROR;
            response.message = 'Unable to load AI Insights. Please try again later.';
        }

        return response;
    }

    public static String askQuestion(Id fileStorageId, String question) {
        System.debug(LoggingLevel.DEBUG, 'FraFileStorageAiInsightsService.askQuestion started. fileStorageId=' + fileStorageId);

        if (fileStorageId == null) {
            throw new AuraHandledException('File Storage record is required.');
        }
        if (String.isBlank(question)) {
            throw new AuraHandledException('Question is required.');
        }

        ResolutionContext context = resolveContext(fileStorageId, true);
        if (context.attachment == null) {
            return 'AI Insights not available for this file yet.';
        }

        InsightsResponse response = context.response;
        hydrateFileStorageResponse(response, context.fileStorage, context.originalFileName);
        if (context.contentVersion != null) {
            response.contentDocumentId = String.valueOf(context.contentVersion.ContentDocumentId);
            response.contentVersionId = String.valueOf(context.contentVersion.Id);
            response.fileInfo = buildFileInfo(context.contentVersion);
        }
        parseAttachmentBody(context.attachment, response);

        String plainText = String.isNotBlank(response.plainTextContext)
            ? response.plainTextContext
            : buildPlainTextContext(response);
        if (String.isBlank(plainText)) {
            return 'AI Insights not available for this file yet.';
        }
        if (plainText.length() > 30000) {
            plainText = plainText.substring(0, 30000) + '\n[Truncated]';
        }

        String prompt =
            'You are answering a follow-up question using saved AI analytics extracted from a healthcare document. ' +
            'Rely only on the saved analytics below. If a detail is not present, say it is not documented.\n\n' +
            'File: ' + response.originalFileName + '\n' +
            'User Question: ' + question.trim() + '\n\n' +
            'Saved AI Analytics:\n' + plainText;

        return callGemini(prompt);
    }

    @TestVisible
    static String extractOriginalFileName(String fileStorageName) {
        if (String.isBlank(fileStorageName)) {
            return fileStorageName;
        }

        String marker = ' - ai generated summary';
        String lower = fileStorageName.toLowerCase();
        Integer markerIndex = lower.lastIndexOf(marker);
        if (markerIndex < 0) {
            return fileStorageName.trim();
        }
        return fileStorageName.substring(0, markerIndex).trim();
    }

    private static ResolutionContext resolveContext(Id fileStorageId, Boolean includeAttachmentBody) {
        ResolutionContext context = new ResolutionContext();
        context.response = newBaseResponse();

        List<fra__File_Storage__c> fileStorages = [
            SELECT Id, Name, fra__Object_RecordId__c, fra__Uploaded_Drive__c, fra__File_URL__c, fra__View_File__c,
                   Document_Id__c
            FROM fra__File_Storage__c
            WHERE Id = :fileStorageId
            LIMIT 1
        ];

        if (fileStorages.isEmpty()) {
            context.response.status = STATUS_ERROR;
            context.response.message = 'File Storage record was not found.';
            return context;
        }

        context.fileStorage = fileStorages[0];
        context.originalFileName = extractOriginalFileName(context.fileStorage.Name);
        hydrateFileStorageResponse(context.response, context.fileStorage, context.originalFileName);
        System.debug(LoggingLevel.DEBUG, 'Extracted original filename=' + context.originalFileName + ' from fileStorageName=' + context.fileStorage.Name);

        Id parentRecordId = parseId(context.fileStorage.fra__Object_RecordId__c);
        Object rawDocumentId = context.fileStorage.get('Document_Id__c');
        String documentIdValue = rawDocumentId == null ? null : String.valueOf(rawDocumentId);
        Id documentId = parseContentDocumentId(documentIdValue);
        if (String.isNotBlank(documentIdValue) && documentId == null) {
            context.response.status = STATUS_NO_CONTENT_DOCUMENT;
            context.response.message = 'File Storage Document Id is not a valid Salesforce ContentDocumentId.';
            return context;
        }

        if (documentId != null) {
            return resolveContextByDocumentId(context, documentId, includeAttachmentBody);
        }

        if (String.isBlank(context.originalFileName)) {
            context.response.status = STATUS_NO_CONTENT_DOCUMENT;
            context.response.message = 'Document Id is missing and original file name could not be determined.';
            return context;
        }

        List<ContentVersion> contentVersions = findMatchingContentVersions(context.originalFileName, parentRecordId);
        if (contentVersions.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'No matching ContentDocument found for originalFileName=' + context.originalFileName);
            context.response.status = STATUS_NO_CONTENT_DOCUMENT;
            context.response.message = 'No matching original Salesforce file was found for this File Storage record.';
            return context;
        }

        Map<Id, Attachment> attachmentsByContentDocumentId = findLatestAnalysisAttachments(contentVersions, parentRecordId);
        context.contentVersion = chooseContentVersion(contentVersions, attachmentsByContentDocumentId);
        context.response.contentDocumentId = String.valueOf(context.contentVersion.ContentDocumentId);
        context.response.contentVersionId = String.valueOf(context.contentVersion.Id);
        context.attachment = attachmentsByContentDocumentId.get(context.contentVersion.ContentDocumentId);

        if (context.attachment == null) {
            System.debug(LoggingLevel.WARN, 'No AI analysis Attachment found for ContentDocumentId=' + context.contentVersion.ContentDocumentId);
            context.response.status = STATUS_NO_ATTACHMENT;
            context.response.message = 'AI Insights not available.';
            return context;
        }

        context.response.status = STATUS_READY;
        context.response.message = 'AI Insights loaded from saved analysis.';
        context.response.hasInsights = true;
        return context;
    }

    private static ResolutionContext resolveContextByDocumentId(
        ResolutionContext context,
        Id documentId,
        Boolean includeAttachmentBody
    ) {
        ContentVersion latestVersion = findLatestContentVersionByDocumentId(documentId);
        if (latestVersion == null) {
            System.debug(LoggingLevel.WARN, 'No latest ContentVersion found for Document_Id__c=' + documentId);
            context.response.status = STATUS_NO_CONTENT_DOCUMENT;
            context.response.message = 'No Salesforce file was found for the File Storage Document Id.';
            return context;
        }

        context.contentVersion = latestVersion;
        if (String.isBlank(context.originalFileName)) {
            context.originalFileName = latestVersion.Title;
            hydrateFileStorageResponse(context.response, context.fileStorage, context.originalFileName);
        }
        context.response.contentDocumentId = String.valueOf(latestVersion.ContentDocumentId);
        context.response.contentVersionId = String.valueOf(latestVersion.Id);
        context.attachment = GeminiAnalysisNoteService.getStoredAnalysisAttachment(documentId, includeAttachmentBody);

        if (context.attachment == null) {
            System.debug(LoggingLevel.WARN, 'No AI analysis Attachment found for Document_Id__c=' + documentId);
            context.response.status = STATUS_NO_ATTACHMENT;
            context.response.message = 'AI Insights not available.';
            return context;
        }

        context.response.status = STATUS_READY;
        context.response.message = 'AI Insights loaded from saved analysis.';
        context.response.hasInsights = true;
        return context;
    }

    private static ContentVersion findLatestContentVersionByDocumentId(Id documentId) {
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, PathOnClient, FileType, ContentSize, CreatedDate, Owner.Name,
                   FirstPublishLocationId, Organization_Name__c
            FROM ContentVersion
            WHERE ContentDocumentId = :documentId
            AND IsLatest = true
            LIMIT 1
        ];

        return versions.isEmpty() ? null : versions[0];
    }

    private static List<ContentVersion> findMatchingContentVersions(String originalFileName, Id parentRecordId) {
        Set<String> candidateNames = buildCandidateNames(originalFileName);
        System.debug(LoggingLevel.DEBUG, 'ContentVersion candidate names=' + candidateNames + ', parentRecordId=' + parentRecordId);

        List<ContentVersion> candidates = [
            SELECT Id, ContentDocumentId, Title, PathOnClient, FileType, ContentSize, CreatedDate, Owner.Name,
                   FirstPublishLocationId, Organization_Name__c
            FROM ContentVersion
            WHERE IsLatest = true
            AND (Title IN :candidateNames OR PathOnClient IN :candidateNames)
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 50
        ];

        if (candidates.isEmpty()) {
            return new List<ContentVersion>();
        }

        if (parentRecordId != null) {
            List<ContentVersion> parentMatches = new List<ContentVersion>();
            for (ContentVersion candidate : candidates) {
                if (candidate.FirstPublishLocationId == parentRecordId) {
                    parentMatches.add(candidate);
                }
            }
            if (!parentMatches.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, 'Found parent-matched ContentVersions=' + parentMatches.size());
                return parentMatches;
            }
        }

        System.debug(LoggingLevel.DEBUG, 'Found matching ContentVersions without parent constraint=' + candidates.size());
        return candidates;
    }

    private static ContentVersion chooseContentVersion(
        List<ContentVersion> contentVersions,
        Map<Id, Attachment> attachmentsByContentDocumentId
    ) {
        for (ContentVersion candidate : contentVersions) {
            if (attachmentsByContentDocumentId.containsKey(candidate.ContentDocumentId)) {
                System.debug(LoggingLevel.DEBUG, 'Selected ContentVersion with analysis Attachment=' + candidate.Id + ', ContentDocumentId=' + candidate.ContentDocumentId);
                return candidate;
            }
        }

        System.debug(LoggingLevel.DEBUG, 'Selected latest ContentVersion without analysis Attachment=' + contentVersions[0].Id + ', ContentDocumentId=' + contentVersions[0].ContentDocumentId);
        return contentVersions[0];
    }

    private static Map<Id, Attachment> findLatestAnalysisAttachments(List<ContentVersion> contentVersions, Id parentRecordId) {
        Map<Id, Attachment> attachmentsByContentDocumentId = new Map<Id, Attachment>();
        Set<String> bracketedIds = new Set<String>();
        Map<String, Id> idByBracketedValue = new Map<String, Id>();
        for (ContentVersion version : contentVersions) {
            String bracketedId = '[' + String.valueOf(version.ContentDocumentId) + ']';
            bracketedIds.add(bracketedId);
            idByBracketedValue.put(bracketedId, version.ContentDocumentId);
        }

        List<String> idLikeClauses = new List<String>();
        for (String bracketedId : bracketedIds) {
            idLikeClauses.add('Name LIKE \'%' + String.escapeSingleQuotes(bracketedId) + '%\'');
        }

        String analysisPattern = '%AI Analysis Store%';
        String attachmentQuery =
            'SELECT Id, Name, ParentId, CreatedDate, LastModifiedDate, Body ' +
            'FROM Attachment WHERE Name LIKE :analysisPattern ' +
            'AND (' + String.join(idLikeClauses, ' OR ') + ') ';
        if (parentRecordId != null) {
            attachmentQuery += 'AND ParentId = :parentRecordId ';
        }
        attachmentQuery += 'ORDER BY CreatedDate DESC, LastModifiedDate DESC LIMIT 200';

        List<Attachment> attachments = Database.query(attachmentQuery);
        for (Attachment attachment : attachments) {
            for (String bracketedId : bracketedIds) {
                Id contentDocumentId = idByBracketedValue.get(bracketedId);
                if (attachment.Name != null &&
                    attachment.Name.contains(bracketedId) &&
                    !attachmentsByContentDocumentId.containsKey(contentDocumentId)) {
                    attachmentsByContentDocumentId.put(contentDocumentId, attachment);
                    System.debug(LoggingLevel.DEBUG, 'Selected Attachment=' + attachment.Id + ', Name=' + attachment.Name);
                }
            }
        }

        return attachmentsByContentDocumentId;
    }

    private static Set<String> buildCandidateNames(String originalFileName) {
        Set<String> names = new Set<String>();
        if (String.isBlank(originalFileName)) {
            return names;
        }

        String trimmed = originalFileName.trim();
        names.add(trimmed);

        Integer dotIndex = trimmed.lastIndexOf('.');
        if (dotIndex > 0) {
            names.add(trimmed.substring(0, dotIndex));
        }

        return names;
    }

    private static void parseAttachmentBody(Attachment attachment, InsightsResponse response) {
        if (attachment == null || attachment.Body == null) {
            response.status = STATUS_NO_ATTACHMENT;
            response.message = 'AI Insights not available.';
            response.hasInsights = false;
            return;
        }

        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(attachment.Body.toString());
            response.analysisTitle = stringValue(raw.get('analysisTitle'));
            response.generatedOn = stringValue(raw.get('generatedOn'));
            response.plainTextContext = stringValue(raw.get('plainTextContext'));
            response.sections = parseSections(raw.get('sections'));
            response.tagGroups = parseTagGroups(raw.get('tagGroups'));
            response.keyFields = parseKeyFields(raw.get('keyFields'));

            if (String.isBlank(response.analysisTitle)) {
                response.analysisTitle = 'Saved AI Analysis';
            }
            if (response.sections.isEmpty() && response.keyFields.isEmpty() && response.tagGroups.isEmpty()) {
                response.status = STATUS_PARSE_ERROR;
                response.message = 'Saved AI Insights were found, but no displayable analytics were available.';
                response.hasInsights = false;
            } else {
                response.status = STATUS_READY;
                response.message = 'AI Insights loaded from saved analysis.';
                response.hasInsights = true;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Failed to parse AI insights Attachment JSON. attachmentId=' + attachment.Id + ', error=' + ex.getMessage());
            response.status = STATUS_PARSE_ERROR;
            response.message = 'Saved AI Insights could not be displayed.';
            response.hasInsights = false;
        }
    }

    private static Map<String, String> parseSections(Object sectionsObj) {
        Map<String, String> sections = new Map<String, String>();
        if (!(sectionsObj instanceof Map<String, Object>)) {
            return sections;
        }

        Map<String, Object> rawSections = (Map<String, Object>) sectionsObj;
        for (String key : rawSections.keySet()) {
            sections.put(key, stringValue(rawSections.get(key)));
        }
        return sections;
    }

    private static List<TagGroupWrapper> parseTagGroups(Object tagGroupsObj) {
        List<TagGroupWrapper> groups = new List<TagGroupWrapper>();
        if (!(tagGroupsObj instanceof List<Object>)) {
            return groups;
        }

        for (Object groupObj : (List<Object>) tagGroupsObj) {
            if (!(groupObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> rawGroup = (Map<String, Object>) groupObj;
            TagGroupWrapper groupRow = new TagGroupWrapper();
            groupRow.category = stringValue(rawGroup.get('category'));
            groupRow.tags = new List<String>();
            Object tagsObj = rawGroup.get('tags');
            if (tagsObj instanceof List<Object>) {
                for (Object tagObj : (List<Object>) tagsObj) {
                    String tagValue = stringValue(tagObj);
                    if (String.isNotBlank(tagValue)) {
                        groupRow.tags.add(tagValue);
                    }
                }
            }
            groups.add(groupRow);
        }
        return groups;
    }

    private static List<KeyFieldWrapper> parseKeyFields(Object keyFieldsObj) {
        List<KeyFieldWrapper> fields = new List<KeyFieldWrapper>();
        if (!(keyFieldsObj instanceof List<Object>)) {
            return fields;
        }

        for (Object fieldObj : (List<Object>) keyFieldsObj) {
            if (!(fieldObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> rawField = (Map<String, Object>) fieldObj;
            KeyFieldWrapper fieldRow = new KeyFieldWrapper();
            fieldRow.groupName = stringValue(rawField.get('groupName'));
            fieldRow.label = stringValue(rawField.get('label'));
            fieldRow.value = stringValue(rawField.get('value'));
            fields.add(fieldRow);
        }
        return fields;
    }

    private static PatientContextWrapper buildPatientContext(ContentVersion version, String parentRecordIdValue) {
        PatientContextWrapper context = new PatientContextWrapper();
        if (version != null && String.isNotBlank(version.Organization_Name__c)) {
            context.organizationName = version.Organization_Name__c;
        }

        Id parentRecordId = parseId(parentRecordIdValue);
        if (parentRecordId == null || parentRecordId.getSObjectType() != Account.SObjectType) {
            return context;
        }

        try {
            List<Account> accounts = [
                SELECT Name, Date_of_Birth__pc, PersonGenderIdentity
                FROM Account
                WHERE Id = :parentRecordId
                LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                Account accountRecord = accounts[0];
                context.patientName = accountRecord.Name;
                context.patientGender = accountRecord.PersonGenderIdentity;
                if (accountRecord.Date_of_Birth__pc != null) {
                    context.patientAge = String.valueOf(calculateAge(accountRecord.Date_of_Birth__pc));
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Unable to load patient context for parentRecordId=' + parentRecordId + ': ' + ex.getMessage());
        }

        return context;
    }

    private static FileInfoWrapper buildFileInfo(ContentVersion version) {
        FileInfoWrapper info = new FileInfoWrapper();
        if (version == null) {
            return info;
        }

        info.title = version.Title;
        info.fileType = version.FileType;
        info.size = formatFileSize(version.ContentSize);
        info.createdDate = version.CreatedDate == null ? null : version.CreatedDate.format('MMM dd, yyyy');
        info.owner = version.Owner == null ? null : version.Owner.Name;
        return info;
    }

    private static String buildPlainTextContext(InsightsResponse response) {
        List<String> parts = new List<String>();
        if (response == null) {
            return '';
        }

        if (response.sections != null) {
            for (String key : response.sections.keySet()) {
                String value = stripHtml(response.sections.get(key));
                if (String.isNotBlank(value) && !isPlaceholder(value)) {
                    parts.add(key + ': ' + value);
                }
            }
        }

        if (response.keyFields != null) {
            List<String> fieldParts = new List<String>();
            for (KeyFieldWrapper fieldRow : response.keyFields) {
                if (fieldRow != null && String.isNotBlank(fieldRow.value) && !isPlaceholder(fieldRow.value)) {
                    fieldParts.add(fieldRow.groupName + ' - ' + fieldRow.label + ': ' + fieldRow.value);
                }
            }
            if (!fieldParts.isEmpty()) {
                parts.add('Key Fields: ' + String.join(fieldParts, ' | '));
            }
        }

        return String.join(parts, '\n\n');
    }

    private static String callGemini(String prompt) {
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.API_Key__c) || String.isBlank(settings.Endpoint__c)) {
            throw new AuraHandledException('Gemini AI is not configured. Please set up Gemini AI Settings.');
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'contents' => new List<Object>{
                new Map<String, Object>{
                    'parts' => new List<Object>{
                        new Map<String, Object>{ 'text' => prompt }
                    }
                }
            },
            'generationConfig' => new Map<String, Object>{
                'temperature' => 0.2,
                'maxOutputTokens' => 2048,
                'candidateCount' => 1
            }
        };

        HttpRequest request = new HttpRequest();
        request.setEndpoint(settings.Endpoint__c + '?key=' + EncodingUtil.urlEncode(settings.API_Key__c, 'UTF-8'));
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(requestBody));
        request.setTimeout(120000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() == 200) {
            return parseGeminiResponse(response.getBody());
        }

        System.debug(LoggingLevel.ERROR, 'Gemini API error in File Storage AI Insights: ' + response.getStatusCode() + ' - ' + response.getBody());
        throw new AuraHandledException('Gemini API returned an error. Please try again.');
    }

    private static String parseGeminiResponse(String responseBody) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> candidates = (List<Object>) responseMap.get('candidates');
        if (candidates == null || candidates.isEmpty()) {
            return 'No response generated by Gemini.';
        }

        Map<String, Object> candidate = (Map<String, Object>) candidates[0];
        Object contentObj = candidate.get('content');
        if (contentObj instanceof Map<String, Object>) {
            Map<String, Object> content = (Map<String, Object>) contentObj;
            Object partsObj = content.get('parts');
            if (partsObj instanceof List<Object> && !((List<Object>) partsObj).isEmpty()) {
                Object partObj = ((List<Object>) partsObj)[0];
                if (partObj instanceof Map<String, Object>) {
                    return stringValue(((Map<String, Object>) partObj).get('text'));
                }
            }
            return stringValue(content.get('text'));
        }
        return 'Unable to parse Gemini response.';
    }

    private static InsightsResponse newBaseResponse() {
        InsightsResponse response = new InsightsResponse();
        response.hasInsights = false;
        response.status = STATUS_ERROR;
        response.message = '';
        response.sections = new Map<String, String>();
        response.tagGroups = new List<TagGroupWrapper>();
        response.keyFields = new List<KeyFieldWrapper>();
        response.patientContext = new PatientContextWrapper();
        response.fileInfo = new FileInfoWrapper();
        return response;
    }

    private static void hydrateFileStorageResponse(InsightsResponse response, fra__File_Storage__c fileStorage, String originalFileName) {
        if (response == null || fileStorage == null) {
            return;
        }
        response.fileStorageId = String.valueOf(fileStorage.Id);
        response.fileStorageName = fileStorage.Name;
        response.uploadedDrive = fileStorage.fra__Uploaded_Drive__c;
        response.parentRecordId = fileStorage.fra__Object_RecordId__c;
        response.originalFileName = originalFileName;
    }

    private static Id parseId(String possibleId) {
        if (String.isBlank(possibleId)) {
            return null;
        }
        try {
            return (Id) possibleId;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id parseContentDocumentId(String possibleId) {
        Id parsedId = parseId(possibleId);
        if (parsedId == null) {
            return null;
        }
        try {
            return parsedId.getSObjectType() == ContentDocument.SObjectType ? parsedId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Integer calculateAge(Date dob) {
        Date today = Date.today();
        Integer age = today.year() - dob.year();
        if (today.month() < dob.month() ||
            (today.month() == dob.month() && today.day() < dob.day())) {
            age--;
        }
        return age;
    }

    private static String stripHtml(String html) {
        if (String.isBlank(html)) {
            return '';
        }
        String text = html.replaceAll('<br\\s*/?>', '\n');
        text = text.replaceAll('</p>', '\n');
        text = text.replaceAll('</li>', '\n');
        text = text.replaceAll('<[^>]*>', '');
        text = text.replaceAll('&amp;', '&');
        text = text.replaceAll('&lt;', '<');
        text = text.replaceAll('&gt;', '>');
        text = text.replaceAll('&nbsp;', ' ');
        text = text.replaceAll('\\s+\\n', '\n');
        text = text.replaceAll('\\n{3,}', '\n\n');
        return text.trim();
    }

    private static Boolean isPlaceholder(String value) {
        if (String.isBlank(value)) {
            return true;
        }
        String normalized = value.trim().toLowerCase();
        return normalized == 'no information available for this section.' ||
            normalized == 'no information available.' ||
            normalized == 'not documented.' ||
            normalized == 'n/a' ||
            normalized == '-' ||
            normalized == 'not stated';
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String formatFileSize(Long sizeInBytes) {
        if (sizeInBytes == null || sizeInBytes == 0) {
            return '0 Bytes';
        }
        if (sizeInBytes < 1024) {
            return sizeInBytes + ' Bytes';
        }
        if (sizeInBytes < 1048576) {
            return Math.round(sizeInBytes / 1024.0) + ' KB';
        }
        return (Decimal.valueOf(sizeInBytes) / 1048576).setScale(1) + ' MB';
    }

    private static void requireReadAccess() {
        if (!fra__File_Storage__c.SObjectType.getDescribe().isAccessible() ||
            !ContentVersion.SObjectType.getDescribe().isAccessible() ||
            !Attachment.SObjectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('You do not have access to load AI Insights.');
        }

        Map<String, Schema.SObjectField> fileStorageFields = fra__File_Storage__c.SObjectType.getDescribe().fields.getMap();
        List<String> requiredFileStorageFields = new List<String>{
            'Name',
            'fra__Object_RecordId__c',
            'fra__Uploaded_Drive__c',
            'fra__File_URL__c',
            'fra__View_File__c',
            'Document_Id__c'
        };
        for (String fieldName : requiredFileStorageFields) {
            if (fileStorageFields.containsKey(fieldName) && !fileStorageFields.get(fieldName).getDescribe().isAccessible()) {
                throw new AuraHandledException('You do not have access to load AI Insights.');
            }
        }
    }
}