/**
 * Service class responsible for making Gemini API callouts to generate
 * AI-based file names for ContentVersion records.
 *
 * Encapsulates prompt construction, HTTP callout, response parsing,
 * and result extraction. Returns a structured CalloutResult so the
 * caller can decide how to handle success/failure.
 */
public with sharing class AiFileNamingCalloutService {

    // Structured result returned from every callout attempt
    public class CalloutResult {
        public Boolean   success        { get; set; }
        public String    fileName       { get; set; }
        public Integer   statusCode     { get; set; }
        public String    errorMessage   { get; set; }
        public String    requestPayload { get; set; }
        public String    responseBody   { get; set; }
        public String    status         { get; set; } // Success, API_Error, Invalid_Response, No_Match, Exception, Config_Missing

        public CalloutResult() {
            this.success = false;
        }
    }

    private static final Integer CALLOUT_TIMEOUT_MS = 120000;

    /**
     * Attempt to generate a file name for the given ContentVersion
     * using the Gemini API. Requires active naming rules.
     *
     * @param rules    Active AI_File_Naming_Rule__c records (ordered by priority)
     * @param account  The Account linked to the ContentVersion
     * @param cv       The ContentVersion record (must include VersionData)
     * @return CalloutResult with success/failure details
     */
    public static CalloutResult generateFileName(
        List<AI_File_Naming_Rule__c> rules,
        Account accountRecord,
        ContentVersion cv
    ) {
        CalloutResult result = new CalloutResult();

        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.API_Key__c) || String.isBlank(settings.Endpoint__c)) {
            result.status = 'Config_Missing';
            result.errorMessage = 'Gemini API settings are not configured (API_Key__c or Endpoint__c missing).';
            return result;
        }

        // Try each rule in priority order; first match wins
        for (AI_File_Naming_Rule__c rule : rules) {
            CalloutResult ruleResult = attemptRuleCallout(settings, rule, accountRecord, cv);
            if (ruleResult.success) {
                return ruleResult;
            }
            // If callout failed with an API/exception error, return immediately
            // rather than burning more callouts on subsequent rules
            if (ruleResult.status == 'API_Error' || ruleResult.status == 'Exception') {
                return ruleResult;
            }
            // No_Match or Invalid_Response for this rule — try next rule
            result = ruleResult;
        }

        // No rule matched
        if (result.status == null) {
            result.status = 'No_Match';
            result.errorMessage = 'No active rules matched this file.';
        }
        return result;
    }

    /**
     * Single-rule callout attempt. Builds prompt, sends request, parses response.
     */
    private static CalloutResult attemptRuleCallout(
        Gemini_AI_Settings__c settings,
        AI_File_Naming_Rule__c rule,
        Account accountRecord,
        ContentVersion cv
    ) {
        CalloutResult result = new CalloutResult();
        String prompt = buildPrompt(rule, accountRecord, cv);

        // Build multimodal request parts
        List<Object> parts = new List<Object>();
        parts.add(new Map<String, Object>{ 'text' => prompt });

        if (cv.VersionData != null) {
            String mimeType = getMimeType(cv.FileType);
            if (String.isNotBlank(mimeType)) {
                parts.add(new Map<String, Object>{
                    'inline_data' => new Map<String, Object>{
                        'mime_type' => mimeType,
                        'data'      => EncodingUtil.base64Encode(cv.VersionData)
                    }
                });
            }
        }

        String requestBody = JSON.serialize(new Map<String, Object>{
            'contents' => new List<Object>{
                new Map<String, Object>{
                    'role'  => 'user',
                    'parts' => parts
                }
            }
        });

        // Store prompt-only payload for logging (exclude base64 binary data)
        result.requestPayload = prompt;

        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(settings.Endpoint__c + '?key=' + EncodingUtil.urlEncode(settings.API_Key__c, 'UTF-8'));
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(CALLOUT_TIMEOUT_MS);
            request.setBody(requestBody);

            HttpResponse response = new Http().send(request);
            result.statusCode = response.getStatusCode();
            result.responseBody = response.getBody();

            if (result.statusCode < 200 || result.statusCode > 299) {
                result.status = 'API_Error';
                result.errorMessage = 'HTTP ' + result.statusCode + ': ' + safeSubstring(response.getBody(), 500);
                return result;
            }

            // Parse the Gemini response
            String text = parseGeminiText(response.getBody());
            if (String.isBlank(text)) {
                result.status = 'Invalid_Response';
                result.errorMessage = 'Gemini returned empty or unparseable text content.';
                return result;
            }

            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(extractJson(text));
            Boolean matched = parsed.containsKey('matched') ? (Boolean) parsed.get('matched') : false;

            if (!matched) {
                result.status = 'No_Match';
                result.errorMessage = 'AI determined this rule does not match the file.';
                return result;
            }

            String fileName = String.valueOf(parsed.get('fileName'));
            if (String.isBlank(fileName)) {
                result.status = 'Invalid_Response';
                result.errorMessage = 'AI matched but returned blank fileName.';
                return result;
            }

            result.success = true;
            result.status = 'Success';
            result.fileName = sanitizeFileName(fileName);
            return result;

        } catch (System.CalloutException calloutEx) {
            result.status = 'API_Error';
            result.errorMessage = 'CalloutException: ' + calloutEx.getMessage();
            return result;
        } catch (Exception ex) {
            result.status = 'Exception';
            result.errorMessage = ex.getTypeName() + ': ' + ex.getMessage() + '\n' + ex.getStackTraceString();
            return result;
        }
    }

    private static String buildPrompt(
        AI_File_Naming_Rule__c rule,
        Account accountRecord,
        ContentVersion cv
    ) {
        return 'You are deciding whether a Salesforce file naming rule applies and generating a clean file name.\n'
            + 'Return ONLY JSON with keys "matched" (boolean) and "fileName" (string).\n\n'
            + '--- METADATA ---\n'
            + 'Account Name: ' + accountRecord.Name + '\n'
            + 'Current File Title: ' + cv.Title + '\n'
            + 'File Type: ' + cv.FileType + '\n'
            + 'Uploaded On: ' + String.valueOf(cv.CreatedDate) + '\n\n'
            + '--- RULE ---\n'
            + 'Rule Name: ' + rule.Name + '\n'
            + 'Rule Criteria Mode: ' + rule.Criteria_Mode__c + '\n'
            + 'Rule Criteria Prompt: ' + rule.Criteria_Prompt__c + '\n'
            + 'Rule Tags: ' + rule.Tags__c + '\n'
            + 'Rule Action Prompt: ' + rule.Action_Prompt__c + '\n\n'
            + '--- STANDARDIZED CATEGORIES (use EXACTLY as written — no variations, abbreviations, or plurals) ---\n'
            + 'Select the single best-matching category by comparing the document content to the description below:\n'
            + '- Progress Note: Patient encounters.\n'
            + '- Consult Report: From specialists.\n'
            + '- Procedure Report: Surgical reports.\n'
            + '- Admission Note: Reason for a patient\'s hospital admission.\n'
            + '- Discharge Summary: Summarize the hospital stay and discharge plans.\n'
            + '- Laboratory Report: Laboratory reports, i.e., blood tests, pathology reports, microbiology, etc.\n'
            + '- Imaging: Radiology reports, i.e., X-rays, MRIs, CT scans, Ultrasounds, etc.\n'
            + '- Diagnostic Report: Other diagnostic studies like EKG, ECG, EMG, echocardiogram, etc.\n'
            + '- ADT: Real-time data tracking a patient\'s location and status within a hospital (Admission, Discharge, Transfer).\n'
            + '- Continuity of Care Document: For interoperability between different EHR systems.\n'
            + '- Care Summary: Summary of patient care across providers or visits.\n'
            + '- Visit Summary: Summary of a patient visit.\n'
            + '- Immunizations: Vaccination history.\n'
            + '- Medication List: List of current and past medications.\n'
            + '- Problem List: Summary of active and resolved diagnoses.\n'
            + '- Care Plan: Treatment and care planning documentation.\n'
            + '- Referrals: Referral documentation to other providers.\n'
            + '- Authorizations: Prior authorization and approvals.\n'
            + '- Insurance: Insurance-related documents.\n'
            + '- Correspondence: General communications.\n'
            + '- Provider Communication: Communication between healthcare providers.\n'
            + '- Coordination Notes: Notes related to care coordination.\n'
            + '- Follow-Up Tracking: Tracking follow-up actions or appointments.\n'
            + '- Consent Forms: Patient consent documentation.\n'
            + '- Billing Claims Data: Information used in reimbursement.\n'
            + '- Administrative: Registration and demographic only information.\n'
            + '- Nursing Notes: Hospital documentation of care, vital signs and assessments performed by nursing staff.\n\n'
            + '--- DATE OF SERVICE ---\n'
            + 'If the Action Prompt requires a date of service, extract it from the DOCUMENT CONTENT itself — '
            + 'this is the date the patient actually received the service (often printed at the top of the document '
            + 'with a date & time, or labeled as "Date of Service", "Service Date", "Collected", "Exam Date", "Visit Date", etc.). '
            + 'Do NOT use the upload date or today\'s date. Format the extracted date as YYYY-MM-DD. '
            + 'If multiple dates appear, choose the actual date of service (not the report/print/signed date). '
            + 'If no date of service can be found in the document, omit it rather than guessing.\n\n'
            + '--- DATE FORMAT INTERPRETATION (IMPORTANT) ---\n'
            + 'Dates in source documents may appear in many formats. Interpret them correctly BEFORE converting to YYYY-MM-DD:\n'
            + '- If the date is already ISO (YYYY-MM-DD or YYYY/MM/DD), use it as-is.\n'
            + '- If the date is clearly written (e.g., "April 3, 2013", "3 Apr 2013", "Apr 03, 2013"), parse by the month name.\n'
            + '- For purely numeric dates like DD/MM/YYYY, MM/DD/YYYY, DD-MM-YY, MM-DD-YY, etc., DO NOT blindly assume one order. '
            + 'Determine the order using these rules in priority:\n'
            + '  1. If one of the first two numbers is > 12, that number MUST be the day (e.g., 13/04/2013 => day=13, month=04 => 2013-04-13).\n'
            + '  2. Look for explicit labels next to the date: "DOB:", "Date of Service:", "DOS:", "Exam Date:", "Collected:", headers, or country/locale hints (US facilities typically use MM/DD/YYYY; most other regions use DD/MM/YYYY).\n'
            + '  3. Check surrounding dates in the same document for consistency — they usually share one format.\n'
            + '  4. If still ambiguous (both numbers <= 12 and no locale hint), default to MM/DD/YYYY for US-based providers/facilities, otherwise DD/MM/YYYY.\n'
            + '- NEVER swap day and month positions silently. The value at the day position stays the day; the value at the month position stays the month. Only the output ORDER changes to YYYY-MM-DD.\n'
            + '- Two-digit years: 00-49 => 20xx, 50-99 => 19xx, unless context clearly says otherwise.\n'
            + 'Example: Document shows "04/03/2013" at a UK clinic => DD/MM/YYYY => 2013-03-04. Same string at a US clinic => MM/DD/YYYY => 2013-04-03. Document shows "15/04/2013" => day must be 15 => 2013-04-15.\n\n'
            + '--- INSTRUCTIONS ---\n'
            + 'The actual file content is attached below for your analysis.\n'
            + 'Carefully read and understand the document content to determine whether the rule applies '
            + 'and to classify it into exactly one of the Standardized Categories above based on the description match.\n'
            + 'If the rule does NOT match the document content, return {"matched":false,"fileName":""}.\n'
            + 'If it matches, generate a concise, clean filename based on the Action Prompt and the '
            + 'actual content you read from the document (using the extracted date of service and the exact '
            + 'standardized category name when applicable). Do not include unsafe file-system characters.';
    }

    @TestVisible
    private static String parseGeminiText(String responseBody) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> candidates = (List<Object>) responseMap.get('candidates');
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }
        Map<String, Object> candidate = (Map<String, Object>) candidates[0];
        Map<String, Object> content = (Map<String, Object>) candidate.get('content');
        if (content == null) {
            return null;
        }
        List<Object> parts = (List<Object>) content.get('parts');
        if (parts == null || parts.isEmpty()) {
            return null;
        }
        Map<String, Object> part = (Map<String, Object>) parts[0];
        return (String) part.get('text');
    }

    @TestVisible
    private static String extractJson(String text) {
        String cleaned = text == null ? '' : text.trim();
        if (cleaned.startsWith('```')) {
            cleaned = cleaned.replace('```json', '').replace('```', '').trim();
        }
        Integer startIndex = cleaned.indexOf('{');
        Integer endIndex = cleaned.lastIndexOf('}');
        if (startIndex >= 0 && endIndex > startIndex) {
            return cleaned.substring(startIndex, endIndex + 1);
        }
        return cleaned;
    }

    private static String sanitizeFileName(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.replaceAll('[\\\\/:*?"<>|#%{}~&]', ' ')
                     .replaceAll('\\s+', ' ')
                     .trim()
                     .left(255);
    }

    /**
     * Maps Salesforce ContentVersion.FileType to a Gemini-supported MIME type.
     * Salesforce returns standardized codes (e.g. TEXT, EXCEL_X, WORD_X, POWER_POINT_X, HTM, JPG)
     * — NOT file extensions — so the lookup is keyed on those uppercase codes.
     * Returns null when the format is not supported by Gemini's inline_data; the caller
     * must then send the prompt with metadata only and skip the binary payload.
     */
    @TestVisible
    private static String getMimeType(String fileType) {
        if (String.isBlank(fileType)) {
            return null;
        }
        String ft = fileType.toUpperCase();
        Map<String, String> mimeMap = new Map<String, String>{
            // Documents (Gemini-supported)
            'PDF'      => 'application/pdf',
            'TEXT'     => 'text/plain',
            'TXT'      => 'text/plain',
            'CSV'      => 'text/csv',
            'HTM'      => 'text/html',
            'HTML'     => 'text/html',
            'XML'      => 'text/xml',
            'JSON'     => 'application/json',
            'RTF'      => 'application/rtf',
            'MARKDOWN' => 'text/markdown',
            'MD'       => 'text/markdown',
            // Images (Gemini-supported)
            'PNG'  => 'image/png',
            'JPG'  => 'image/jpeg',
            'JPEG' => 'image/jpeg',
            'WEBP' => 'image/webp',
            'HEIC' => 'image/heic',
            'HEIF' => 'image/heif'
            // Intentionally NOT mapped (Gemini rejects these as inline_data):
            //   EXCEL / EXCEL_X (xls/xlsx), WORD / WORD_X (doc/docx),
            //   POWER_POINT / POWER_POINT_X (ppt/pptx),
            //   GIF, BMP, SVG, TIFF/TIF, ZIP, and any unknown binary.
            // For these we return null and the caller sends metadata-only.
        };
        return mimeMap.get(ft); // null when unsupported
    }

    private static String safeSubstring(String value, Integer maxLen) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}