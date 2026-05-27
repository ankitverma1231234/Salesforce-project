/**
 * Service class for AI File Naming Test Run feature.
 *
 * Provides a read-only preview of AI-generated file names without
 * performing any DML. Reuses AiFileNamingCalloutService for the
 * actual Gemini API callout.
 */
public with sharing class AiFileNamingTestRunService {

    public class TestRunResult {
        @AuraEnabled public String  suggestedFileName;
        @AuraEnabled public String  criteriaMatched;
        @AuraEnabled public String  actionUsed;
        @AuraEnabled public String  summary;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  errorMessage;
    }

    /**
     * Execute a test run for a single rule against a selected account and file.
     * Makes a real Gemini API callout but does NOT update any records.
     *
     * @param ruleId             The AI_File_Naming_Rule__c to test
     * @param accountId          The Account (Person Account) to use as context
     * @param contentDocumentId  The ContentDocument whose latest version will be sent to AI
     * @return TestRunResult with the AI-suggested file name or error details
     */
    public static TestRunResult runTest(Id ruleId, Id accountId, Id contentDocumentId) {
        TestRunResult result = new TestRunResult();

        // ── Query the rule ──
        List<AI_File_Naming_Rule__c> ruleList = [
            SELECT Id, Name, Order__c, Is_Active__c, Criteria_Mode__c,
                   Criteria_Prompt__c, Tags__c, Action_Prompt__c
            FROM AI_File_Naming_Rule__c
            WHERE Id = :ruleId
            LIMIT 1
        ];
        if (ruleList.isEmpty()) {
            result.success = false;
            result.errorMessage = 'Rule not found.';
            result.summary = 'The selected rule could not be found.';
            return result;
        }
        AI_File_Naming_Rule__c rule = ruleList[0];

        // ── Query the account ──
        List<Account> accList = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accList.isEmpty()) {
            result.success = false;
            result.errorMessage = 'Account not found.';
            result.summary = 'The selected account could not be found.';
            return result;
        }
        Account acc = accList[0];

        // ── Query the latest ContentVersion (including VersionData for AI) ──
        List<ContentVersion> cvList = [
            SELECT Id, ContentDocumentId, Title, FileType, CreatedDate, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
              AND IsLatest = true
            LIMIT 1
        ];
        if (cvList.isEmpty()) {
            result.success = false;
            result.errorMessage = 'No file version found for the selected document.';
            result.summary = 'Could not locate the latest version of the selected file.';
            return result;
        }
        ContentVersion cv = cvList[0];

        // ── Call the Gemini AI via existing callout service ──
        List<AI_File_Naming_Rule__c> singleRule = new List<AI_File_Naming_Rule__c>{ rule };
        AiFileNamingCalloutService.CalloutResult calloutResult =
            AiFileNamingCalloutService.generateFileName(singleRule, acc, cv);

        // ── Map callout result to test run result ──
        result.success = calloutResult.success;
        result.criteriaMatched = buildCriteriaSummary(rule);
        result.actionUsed = rule.Action_Prompt__c != null
            ? rule.Action_Prompt__c.abbreviate(100)
            : '';

        if (calloutResult.success && String.isNotBlank(calloutResult.fileName)) {
            result.suggestedFileName = calloutResult.fileName;
            result.summary = 'AI successfully generated a file name. No changes were saved.';
        } else {
            result.suggestedFileName = null;

            // Friendly message for 503 (Gemini overloaded)
            if (calloutResult.statusCode != null && calloutResult.statusCode == 503) {
                result.errorMessage = 'HTTP 503';
                result.summary = 'Gemini experiencing high demand. Spikes in demand are usually temporary. Please try again later.';
            } else {
                result.errorMessage = calloutResult.errorMessage;
                result.summary = 'Status: ' + calloutResult.status + '. '
                    + (String.isNotBlank(calloutResult.errorMessage) ? calloutResult.errorMessage : 'No file name generated.');
            }
        }

        return result;
    }

    private static String buildCriteriaSummary(AI_File_Naming_Rule__c rule) {
        String summary = 'Mode: ' + rule.Criteria_Mode__c;
        if (String.isNotBlank(rule.Criteria_Prompt__c)) {
            summary += ' | Prompt: ' + rule.Criteria_Prompt__c.abbreviate(50);
        }
        if (String.isNotBlank(rule.Tags__c)) {
            summary += ' | Tags: ' + rule.Tags__c;
        }
        return summary;
    }
}