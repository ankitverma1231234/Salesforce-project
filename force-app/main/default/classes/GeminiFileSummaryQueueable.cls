public class GeminiFileSummaryQueueable implements Queueable, Database.AllowsCallouts {

    private Id contentVersionId;

    public GeminiFileSummaryQueueable(Id contentVersionId) {
        this.contentVersionId = contentVersionId;
    }

    public void execute(QueueableContext context) {
        try {
            ContentVersion cv = [
                SELECT Id, ContentDocumentId, Title, FileType, VersionData
                FROM ContentVersion
                WHERE Id = :this.contentVersionId
                LIMIT 1
            ];

            String fileContent = extractFileContent(cv);
            if (String.isBlank(fileContent)) {
                cacheResult(cv.ContentDocumentId, 'Unable to extract text content from this file type (' + cv.FileType + ').');
                return;
            }

            // Truncate to ~30K chars to stay within Gemini limits and Apex heap
            if (fileContent.length() > 30000) {
                fileContent = fileContent.substring(0, 30000) + '\n\n[Content truncated...]';
            }

            String summary = callGeminiForSummary(fileContent, cv.Title);
            cacheResult(cv.ContentDocumentId, summary);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'GeminiFileSummaryQueueable error: ' + e.getMessage());
        }
    }

    private String extractFileContent(ContentVersion cv) {
        if (cv.VersionData == null) {
            return null;
        }

        String fileType = cv.FileType != null ? cv.FileType.toUpperCase() : '';

        // Text-based files: decode blob to string directly
        Set<String> textTypes = new Set<String>{
            'TEXT', 'TXT', 'CSV', 'XML', 'HTML', 'JSON', 'RTF', 'LOG', 'MD'
        };

        if (textTypes.contains(fileType)) {
            return cv.VersionData.toString();
        }

        // For PDF and other binary types: send as base64 to Gemini
        // Gemini can handle inline document data
        if (fileType == 'PDF') {
            return 'BASE64_PDF:' + EncodingUtil.base64Encode(cv.VersionData);
        }

        // For Word docs and other formats, attempt string conversion
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

    private String callGeminiForSummary(String fileContent, String fileName) {
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.API_Key__c) || String.isBlank(settings.Endpoint__c)) {
            return 'Gemini AI is not configured. Please set up Gemini AI Settings.';
        }

        String endpoint = settings.Endpoint__c + '?key=' + settings.API_Key__c;

        Map<String, Object> requestBody;

        // Handle PDF files with inline_data
        if (fileContent.startsWith('BASE64_PDF:')) {
            String base64Data = fileContent.substringAfter('BASE64_PDF:');
            requestBody = buildPdfRequestBody(base64Data, fileName);
        } else {
            requestBody = buildTextRequestBody(fileContent, fileName);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(requestBody));
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            return parseGeminiResponse(res.getBody());
        } else {
            System.debug(LoggingLevel.ERROR, 'Gemini API error: ' + res.getStatusCode() + ' - ' + res.getBody());
            return 'Error generating summary. Status: ' + res.getStatusCode();
        }
    }

    private Map<String, Object> buildTextRequestBody(String fileContent, String fileName) {
        String prompt = 'You are a document analyst. Analyze the following file and provide:\n'
            + '1. **Summary**: A concise 2-3 sentence summary of the document.\n'
            + '2. **Key Insights**: 3-5 bullet points highlighting the most important information.\n'
            + '3. **Document Type**: What type of document this appears to be.\n\n'
            + 'File Name: ' + fileName + '\n\n'
            + 'Content:\n' + fileContent;

        Map<String, Object> textPart = new Map<String, Object>{ 'text' => prompt };
        List<Object> parts = new List<Object>{ textPart };
        Map<String, Object> content = new Map<String, Object>{
            'role' => 'user',
            'parts' => parts
        };
        return new Map<String, Object>{
            'contents' => new List<Object>{ content }
        };
    }

    private Map<String, Object> buildPdfRequestBody(String base64Data, String fileName) {
        String prompt = 'You are a document analyst. Analyze the following PDF file and provide:\n'
            + '1. **Summary**: A concise 2-3 sentence summary of the document.\n'
            + '2. **Key Insights**: 3-5 bullet points highlighting the most important information.\n'
            + '3. **Document Type**: What type of document this appears to be.\n\n'
            + 'File Name: ' + fileName;

        Map<String, Object> textPart = new Map<String, Object>{ 'text' => prompt };
        Map<String, Object> inlineData = new Map<String, Object>{
            'mime_type' => 'application/pdf',
            'data' => base64Data
        };
        Map<String, Object> filePart = new Map<String, Object>{ 'inline_data' => inlineData };

        List<Object> parts = new List<Object>{ textPart, filePart };
        Map<String, Object> content = new Map<String, Object>{
            'role' => 'user',
            'parts' => parts
        };
        return new Map<String, Object>{
            'contents' => new List<Object>{ content }
        };
    }

    private String parseGeminiResponse(String responseBody) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> candidates = (List<Object>) responseMap.get('candidates');
        if (candidates == null || candidates.isEmpty()) {
            return 'No response generated by Gemini.';
        }
        Map<String, Object> candidate = (Map<String, Object>) candidates[0];
        Map<String, Object> contentMap = (Map<String, Object>) candidate.get('content');
        List<Object> parts = (List<Object>) contentMap.get('parts');
        if (parts == null || parts.isEmpty()) {
            return 'Empty response from Gemini.';
        }
        Map<String, Object> part = (Map<String, Object>) parts[0];
        return (String) part.get('text');
    }

    private void cacheResult(Id contentDocumentId, String summary) {
        try {
            Cache.Org.put(
                'local.GeminiCache.' + String.valueOf(contentDocumentId).left(15),
                summary,
                7200  // TTL: 2 hours
            );
        } catch (Exception e) {
            // Platform Cache partition may not exist; store in fallback
            System.debug(LoggingLevel.WARN, 'Platform Cache not available: ' + e.getMessage());
            GeminiCacheManager.putSummary(contentDocumentId, summary);
        }
    }
}