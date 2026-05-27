public with sharing class AiFileNamingConventionController {

    public class TestResult {
        @AuraEnabled public String suggestedFileName;
        @AuraEnabled public String criteriaMatched;
        @AuraEnabled public String actionUsed;
        @AuraEnabled public String summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<AI_File_Naming_Rule__c> getRules() {
        return [
            SELECT Id, Name, Order__c, Is_Active__c, Criteria_Mode__c, Criteria_Prompt__c,
                   Tags__c, Action_Prompt__c
            FROM AI_File_Naming_Rule__c
            ORDER BY Order__c ASC NULLS LAST, CreatedDate ASC
        ];
    }

    @AuraEnabled
    public static List<AI_File_Naming_Rule__c> getRulesFresh() {
        return [
            SELECT Id, Name, Order__c, Is_Active__c, Criteria_Mode__c, Criteria_Prompt__c,
                   Tags__c, Action_Prompt__c
            FROM AI_File_Naming_Rule__c
            ORDER BY Order__c ASC NULLS LAST, CreatedDate ASC
        ];
    }

    @AuraEnabled
    public static AI_File_Naming_Rule__c saveRule(AI_File_Naming_Rule__c ruleData) {
        if (ruleData == null) {
            throw new AuraHandledException('Rule data is required.');
        }

        // Validation
        if (String.isBlank(ruleData.Name)) {
            throw new AuraHandledException('Rule Name is required.');
        }
        if (ruleData.Order__c == null || ruleData.Order__c < 1) {
            throw new AuraHandledException('Order must be >= 1.');
        }
        if (String.isBlank(ruleData.Action_Prompt__c)) {
            throw new AuraHandledException('Action Prompt is required.');
        }

        // Criteria validation
        Boolean hasPrompt = String.isNotBlank(ruleData.Criteria_Prompt__c);
        Boolean hasTags = String.isNotBlank(ruleData.Tags__c);
        String mode = String.isBlank(ruleData.Criteria_Mode__c) ? 'prompt_only' : ruleData.Criteria_Mode__c;

        if (mode == 'prompt_only' && !hasPrompt) {
            throw new AuraHandledException('Criteria Prompt is required for prompt_only mode.');
        }
        if (mode == 'tags_only' && !hasTags) {
            throw new AuraHandledException('Tags are required for tags_only mode.');
        }
        if (mode == 'prompt_and_tags' && (!hasPrompt || !hasTags)) {
            throw new AuraHandledException('Both Criteria Prompt and Tags are required for prompt_and_tags mode.');
        }
        if (mode == 'prompt_or_tags' && !hasPrompt && !hasTags) {
            throw new AuraHandledException('Either Criteria Prompt or Tags is required for prompt_or_tags mode.');
        }

        upsert ruleData;
        return ruleData;
    }

    @AuraEnabled
    public static void deleteRule(Id ruleId) {
        if (ruleId == null) {
            throw new AuraHandledException('Rule Id is required.');
        }
        delete new AI_File_Naming_Rule__c(Id = ruleId);
    }

    @AuraEnabled
    public static AI_File_Naming_Rule__c setRuleActive(Id ruleId, Boolean isActive) {
        if (ruleId == null) {
            throw new AuraHandledException('Rule Id is required.');
        }

        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Id = ruleId,
            Is_Active__c = isActive
        );
        update rule;
        return rule;
    }

    @AuraEnabled(cacheable=true)
    public static List<ContentDocument> getFilesForAccount(Id accountId) {
        if (accountId == null) {
            return new List<ContentDocument>();
        }

        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accountId
        ]) {
            contentDocumentIds.add(link.ContentDocumentId);
        }

        return [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static List<Map<String, String>> searchAccounts(String searchTerm) {
        List<Map<String, String>> results = new List<Map<String, String>>();
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return results;
        }

        String likeKey = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        for (Account acc : [
            SELECT Id, Name, PersonEmail
            FROM Account
            WHERE IsPersonAccount = true
              AND (Name LIKE :likeKey OR PersonEmail LIKE :likeKey)
            ORDER BY Name ASC
            LIMIT 20
        ]) {
            Map<String, String> item = new Map<String, String>();
            item.put('id', acc.Id);
            item.put('name', acc.Name);
            item.put('email', acc.PersonEmail != null ? acc.PersonEmail : '');
            results.add(item);
        }
        return results;
    }

    @AuraEnabled
    public static TestResult previewFileName(Id ruleId, Id accountId, Id contentDocumentId) {
        if (ruleId == null || accountId == null || contentDocumentId == null) {
            throw new AuraHandledException('Rule, Account, and File are required.');
        }

        AiFileNamingTestRunService.TestRunResult testRunResult =
            AiFileNamingTestRunService.runTest(ruleId, accountId, contentDocumentId);

        TestResult result = new TestResult();
        result.criteriaMatched = testRunResult.criteriaMatched;
        result.actionUsed = testRunResult.actionUsed;
        result.summary = testRunResult.summary;

        if (testRunResult.success) {
            result.suggestedFileName = testRunResult.suggestedFileName;
        } else {
            result.suggestedFileName = testRunResult.errorMessage != null
                ? 'Error: ' + testRunResult.errorMessage
                : 'No file name generated';
        }

        return result;
    }
}