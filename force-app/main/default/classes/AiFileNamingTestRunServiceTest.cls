@IsTest(SeeAllData=true)
private class AiFileNamingTestRunServiceTest {

    private class GeminiSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(
                '{"candidates":[{"content":{"parts":[{"text":"{\\"matched\\":true,\\"fileName\\":\\"AI Suggested Name.pdf\\"}"}]}}]}'
            );
            return response;
        }
    }

    private class Gemini503Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"error":"Service Unavailable"}');
            return response;
        }
    }

    private class GeminiErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"error":"Internal Server Error"}');
            return response;
        }
    }

    private static Id getOrCreatePersonAccountId() {
        List<Account> existingAccounts = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
              AND PersonEmail != null
              AND PersonMobilePhone != null
            LIMIT 1
        ];
        if (!existingAccounts.isEmpty()) {
            return existingAccounts[0].Id;
        }
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        Account acc = new Account(
            FirstName = 'Test',
            LastName = 'Person',
            RecordTypeId = personAccountRT,
            PersonEmail = 'test.person@example.com',
            PersonMobilePhone = '5551234567'
        );
        insert acc;
        return acc.Id;
    }

    private static void ensureGeminiSettings() {
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        settings.API_Key__c = 'test-key';
        settings.Endpoint__c = 'https://example.com/gemini';
        if (settings.Id != null) {
            update settings;
        } else {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            insert settings;
        }
    }

    private static AI_File_Naming_Rule__c insertRule(String mode, String prompt, String tags) {
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name = 'Test Rule ' + mode,
            Order__c = 1,
            Is_Active__c = true,
            Criteria_Mode__c = mode,
            Criteria_Prompt__c = prompt,
            Tags__c = tags,
            Action_Prompt__c = 'Generate a clean filename.'
        );
        insert rule;
        return rule;
    }

    private static Id insertContentVersionFor(Id accountId) {
        ContentVersion cv = new ContentVersion(
            Title = 'TestRun File',
            PathOnClient = 'TestRunFile.pdf',
            VersionData = Blob.valueOf('test body'),
            FirstPublishLocationId = accountId
        );
        insert cv;
        return [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ].ContentDocumentId;
    }

    @IsTest
    static void runTestSuccessPath() {
        Id accountId = getOrCreatePersonAccountId();
        ensureGeminiSettings();
        AI_File_Naming_Rule__c rule = insertRule('prompt_and_tags', 'Match radiology docs', 'radiology');
        Id contentDocumentId = insertContentVersionFor(accountId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiSuccessMock());
        AiFileNamingTestRunService.TestRunResult result =
            AiFileNamingTestRunService.runTest(rule.Id, accountId, contentDocumentId);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Expected success');
        System.assertNotEquals(null, result.suggestedFileName);
        System.assertNotEquals(null, result.criteriaMatched);
        System.assertNotEquals(null, result.actionUsed);
    }

    @IsTest
    static void runTestRuleNotFound() {
        Id accountId = getOrCreatePersonAccountId();
        Id contentDocumentId = insertContentVersionFor(accountId);
        Id fakeRuleId = 'a00000000000000AAA';

        Test.startTest();
        AiFileNamingTestRunService.TestRunResult result =
            AiFileNamingTestRunService.runTest(fakeRuleId, accountId, contentDocumentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('Rule not found.', result.errorMessage);
    }

    @IsTest
    static void runTestAccountNotFound() {
        AI_File_Naming_Rule__c rule = insertRule('tags_only', null, 'lab');
        Id fakeAccountId = '001000000000000AAA';
        Id accountId = getOrCreatePersonAccountId();
        Id contentDocumentId = insertContentVersionFor(accountId);

        Test.startTest();
        AiFileNamingTestRunService.TestRunResult result =
            AiFileNamingTestRunService.runTest(rule.Id, fakeAccountId, contentDocumentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('Account not found.', result.errorMessage);
    }

    @IsTest
    static void runTestContentDocumentNotFound() {
        Id accountId = getOrCreatePersonAccountId();
        AI_File_Naming_Rule__c rule = insertRule('prompt_only', 'Match all', null);
        Id fakeDocId = '069000000000000AAA';

        Test.startTest();
        AiFileNamingTestRunService.TestRunResult result =
            AiFileNamingTestRunService.runTest(rule.Id, accountId, fakeDocId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('No file version found for the selected document.', result.errorMessage);
    }

    @IsTest
    static void runTestGemini503ReturnsFriendlyMessage() {
        Id accountId = getOrCreatePersonAccountId();
        ensureGeminiSettings();
        AI_File_Naming_Rule__c rule = insertRule('tags_only', null, 'imaging');
        Id contentDocumentId = insertContentVersionFor(accountId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new Gemini503Mock());
        AiFileNamingTestRunService.TestRunResult result =
            AiFileNamingTestRunService.runTest(rule.Id, accountId, contentDocumentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('HTTP 503', result.errorMessage);
        System.assert(result.summary.contains('high demand'), 'Expected friendly 503 message');
    }

    @IsTest
    static void runTestGenericApiError() {
        Id accountId = getOrCreatePersonAccountId();
        ensureGeminiSettings();
        AI_File_Naming_Rule__c rule = insertRule('prompt_or_tags', 'Any file', 'misc');
        Id contentDocumentId = insertContentVersionFor(accountId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiErrorMock());
        AiFileNamingTestRunService.TestRunResult result =
            AiFileNamingTestRunService.runTest(rule.Id, accountId, contentDocumentId);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertNotEquals(null, result.summary);
    }
}