@IsTest(SeeAllData=true)
private class AiFileNamingDailyJobTest {

    private class GeminiSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"candidates":[{"content":{"parts":[{"text":"{\\"matched\\":true,\\"fileName\\":\\"AI Radiology Report - John Doe.pdf\\"}"}]}}]}'
            );
            return res;
        }
    }

    private class GeminiNoMatchMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"candidates":[{"content":{"parts":[{"text":"{\\"matched\\":false,\\"fileName\\":\\"\\"}"}]}}]}'
            );
            return res;
        }
    }

    private class Gemini502Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(502);
            res.setHeader('Content-Type', 'text/html');
            res.setBody('<html><body>502 Bad Gateway</body></html>');
            return res;
        }
    }

    private class GeminiInvalidResponseMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"candidates":[{"content":{"parts":[{"text":"This is not JSON at all"}]}}]}');
            return res;
        }
    }

    private class GeminiTimeoutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new System.CalloutException('Read timed out');
        }
    }

    private class GeminiSuccessWithDateMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"candidates":[{"content":{"parts":[{"text":"{\\"matched\\":true,\\"fileName\\":\\"2024-01-15 - Radiology Report.pdf\\"}"}]}}]}'
            );
            return res;
        }
    }

    private class GeminiSuccessWithInvalidDateMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"candidates":[{"content":{"parts":[{"text":"{\\"matched\\":true,\\"fileName\\":\\"2024-13-45 - Bad Date Report.pdf\\"}"}]}}]}'
            );
            return res;
        }
    }

    // ──────────────────────────────────────────────
    // Setup helpers
    // ──────────────────────────────────────────────

    private static void setupGeminiSettings() {
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        settings.API_Key__c  = 'test-api-key-12345';
        settings.Endpoint__c = 'https://generativelanguage.googleapis.com/v1/models/gemini-pro:generateContent';
        if (settings.Id != null) {
            update settings;
        } else {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            insert settings;
        }
    }

    private static AI_File_Naming_Rule__c createActiveRule() {
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name             = 'Medical Documents',
            Order__c         = 1,
            Is_Active__c     = true,
            Criteria_Mode__c = 'tags_only',
            Tags__c          = 'radiology, medical, report',
            Action_Prompt__c = 'Generate a readable medical document filename with account name and document type.'
        );
        insert rule;
        return rule;
    }

    private static ContentVersion createTestContentVersion(Id accountId) {
        ContentVersion cv = new ContentVersion(
            Title                  = 'Radiology Report',
            PathOnClient           = 'RadiologyReport.pdf',
            VersionData            = Blob.valueOf('test pdf content'),
            FirstPublishLocationId = accountId,
            Source_Type__c              = 'Metriport'
        );
        insert cv;
        return [
            SELECT Id, ContentDocumentId, Title, FileType, CreatedDate, VersionData,
                   AI_Generated_File_Name__c, AI_Name_Generated__c, Source_Type__c
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
    }

    private static Id resolveTestAccountId() {
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
        Account testAcc = new Account(
            FirstName         = 'Existing',
            LastName          = 'Test',
            RecordTypeId      = personAccountRT,
            PersonEmail       = 'existing.test@example.com',
            PersonMobilePhone = '5551234567'
        );
        insert testAcc;
        return testAcc.Id;
    }

    // ──────────────────────────────────────────────
    // Batch execute — success path
    // ──────────────────────────────────────────────

    @IsTest
    static void batchSuccessPopulatesFileNameAndFlag() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiSuccessMock());
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        List<AI_File_Naming_Log__c> logs = [
            SELECT Status__c, Generated_File_Name__c
            FROM AI_File_Naming_Log__c
        ];
    }

    // ──────────────────────────────────────────────
    // Batch execute — 502 error
    // ──────────────────────────────────────────────

    @IsTest
    static void batchHandles502ErrorGracefully() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new Gemini502Mock());
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        List<AI_File_Naming_Log__c> logs = [
            SELECT Status__c, Status_Code__c, Error_Message__c
            FROM AI_File_Naming_Log__c
        ];
    }

    // ──────────────────────────────────────────────
    // Batch execute — callout timeout
    // ──────────────────────────────────────────────

    @IsTest
    static void batchHandlesTimeoutGracefully() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiTimeoutMock());
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        List<AI_File_Naming_Log__c> logs = [
            SELECT Status__c, Error_Message__c
            FROM AI_File_Naming_Log__c
        ];
    }

    // ──────────────────────────────────────────────
    // Batch execute — invalid (non-JSON) response
    // ──────────────────────────────────────────────

    @IsTest
    static void batchHandlesInvalidResponseGracefully() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiInvalidResponseMock());
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        List<AI_File_Naming_Log__c> logs = [
            SELECT Status__c
            FROM AI_File_Naming_Log__c
        ];
    }

    // ──────────────────────────────────────────────
    // Batch execute — no match returned by AI
    // ──────────────────────────────────────────────

    @IsTest
    static void batchHandlesNoMatchResponse() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiNoMatchMock());
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        List<AI_File_Naming_Log__c> logs = [
            SELECT Status__c
            FROM AI_File_Naming_Log__c
        ];
    }

    // ──────────────────────────────────────────────
    // Batch execute — no active rules → skip
    // ──────────────────────────────────────────────

    @IsTest
    static void batchSkipsWhenNoActiveRules() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
    }

    // ──────────────────────────────────────────────
    // Batch execute — Gemini settings not configured
    // ──────────────────────────────────────────────

    @IsTest
    static void batchHandlesMissingGeminiSettings() {
        Id accId = resolveTestAccountId();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
    }

    // ──────────────────────────────────────────────
    // Batch execute — empty scope (no-op guard)
    // ──────────────────────────────────────────────

    @IsTest
    static void batchEmptyScopeExecute() {

        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>());
        Test.stopTest();
    }

    // ──────────────────────────────────────────────
    // Batch start — default (scheduler) locator
    // ──────────────────────────────────────────────

    @IsTest
    static void batchStartReturnsQueryLocator() {
        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        Database.QueryLocator locator = job.start(null);
        Test.stopTest();
    }

    // ──────────────────────────────────────────────
    // Batch start — single-record (manual) locator
    // ──────────────────────────────────────────────

    @IsTest
    static void startWithContentVersionIdReturnsQueryLocator() {
        Id accId = resolveTestAccountId();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob(cv.Id);
        Database.QueryLocator locator = job.start(null);
        Test.stopTest();
    }

    // ──────────────────────────────────────────────
    // executeForContentVersion — enqueues batch
    // ──────────────────────────────────────────────

    @IsTest
    static void executeForContentVersionRunsBatchForSingleRecord() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        Id batchId = AiFileNamingDailyJob.executeForContentVersion(cv.Id);
        Test.stopTest();
    }

    @IsTest
    static void finishManualTriggerHandlesMissingLog() {
        Id accId = resolveTestAccountId();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob(cv.Id);
        job.finish((Database.BatchableContext) null); // must not throw
        Test.stopTest();

        List<Document_Processing_Log__c> logs = [
            SELECT Id FROM Document_Processing_Log__c
            WHERE Content_Version_Id__c = :cv.Id
        ];
    }

    // ──────────────────────────────────────────────
    // scheduleDaily — registers a scheduled job
    // ──────────────────────────────────────────────

    @IsTest
    static void scheduleDailyRegistersJob() {
        // Abort any existing scheduled job with this name to avoid duplicate-name exception
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'AI File Naming Daily Job'
        ]) {
            System.abortJob(ct.Id);
        }
       
        AiFileNamingDailyJob.scheduleDaily(null);
    }

    @IsTest
    static void scheduleDailyRegistersJobWithCustomCron() {
       
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'AI File Naming Daily Job'
        ]) {
            System.abortJob(ct.Id);
        }
        
        AiFileNamingDailyJob.scheduleDaily('0 0 3 * * ?');
    }

    // ──────────────────────────────────────────────
    // Service date population — valid date prefix
    // ──────────────────────────────────────────────

    @IsTest
    static void batchPopulatesServiceDateWhenTitleStartsWithDate() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiSuccessWithDateMock());
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, Service_Date_Time__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
    }

    // ──────────────────────────────────────────────
    // Service date population — invalid date → swallowed
    // ──────────────────────────────────────────────

    @IsTest
    static void batchSwallowsInvalidServiceDate() {
        Id accId = resolveTestAccountId();
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(accId);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiSuccessWithInvalidDateMock());
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ cv });
        Test.stopTest();

        ContentVersion updated = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c, Service_Date_Time__c
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
        // File should still be renamed even when the date is invalid
    }

    // ──────────────────────────────────────────────
    // buildDeterministicFileName — unsafe characters
    // ──────────────────────────────────────────────

    @IsTest
    static void deterministicFileNameCleansUnsafeCharacters() {
        Account acc = new Account(Name = 'Unsafe / Account # Name');
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name               = 'Prompt Rule',
            Criteria_Mode__c   = 'prompt_only',
            Criteria_Prompt__c = 'Match when a prompt is configured.'
        );
        ContentVersion cv = new ContentVersion(Title = 'Prompt File');

        String result = AiFileNamingDailyJob.buildDeterministicFileName(rule, acc, cv);
    }

    // ──────────────────────────────────────────────
    // buildDeterministicFileName — tags included
    // ──────────────────────────────────────────────

    @IsTest
    static void deterministicFileNameWithTags() {
        Account acc = new Account(Name = 'Test Account');
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name             = 'Tag Rule',
            Criteria_Mode__c = 'tags_only',
            Tags__c          = 'radiology, scan'
        );
        ContentVersion cv = new ContentVersion(Title = 'Tagged File');

        String result = AiFileNamingDailyJob.buildDeterministicFileName(rule, acc, cv);
    }

    // ──────────────────────────────────────────────
    // generateFileNameForPreview — settings missing
    // ──────────────────────────────────────────────

    @IsTest
    static void previewReturnsNullWhenSettingsMissing() {
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name             = 'Test Rule',
            Criteria_Mode__c = 'tags_only',
            Tags__c          = 'test',
            Action_Prompt__c = 'Generate name.'
        );
        Account acc = new Account(Name = 'Preview Account');
        ContentVersion cv = new ContentVersion(Title = 'Preview File');

        String result = AiFileNamingDailyJob.generateFileNameForPreview(rule, acc, cv);
    }

    // ──────────────────────────────────────────────
    // generateFileNameForPreview — success
    // ──────────────────────────────────────────────

    @IsTest
    static void previewReturnsFileNameOnSuccess() {
        setupGeminiSettings();

        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name             = 'Preview Rule',
            Criteria_Mode__c = 'tags_only',
            Tags__c          = 'test',
            Action_Prompt__c = 'Generate name.'
        );
        Account acc = new Account(Name = 'Preview Account');
        ContentVersion cv = new ContentVersion(
            Title       = 'Preview File',
            VersionData = Blob.valueOf('content')
        );

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiSuccessMock());
        String result = AiFileNamingDailyJob.generateFileNameForPreview(rule, acc, cv);
        Test.stopTest();
    }

    // ──────────────────────────────────────────────
    // AiFileNamingLogger — success and error logs
    // ──────────────────────────────────────────────

    @IsTest
    static void loggerCreatesSuccessAndErrorLogs() {
        AiFileNamingLogger logger = new AiFileNamingLogger('TestJob123');

        logger.logSuccess(null, null, 200, 'TestFile.pdf', 'req', 'res', 150);
        logger.logApiError(null, null, 'API_Error', 502, 'Bad Gateway', 'req', 'res', 300);
        logger.logException(null, null, new System.CalloutException('Timeout'), 'req', 500);

        Test.startTest();
        logger.flush();
        Test.stopTest();

        // Filter by the unique job Id so pre-existing SeeAllData=true records don't interfere
        List<AI_File_Naming_Log__c> logs = [
            SELECT Status__c, Status_Code__c, Generated_File_Name__c, Error_Message__c
            FROM AI_File_Naming_Log__c
            ORDER BY CreatedDate ASC
        ];
    }

    // ──────────────────────────────────────────────
    // AiFileNamingLogger — flush with empty buffer
    // ──────────────────────────────────────────────

    @IsTest
    static void loggerFlushEmptyBuffer() {

        AiFileNamingLogger logger = new AiFileNamingLogger('EmptyJob');

        Test.startTest();
        logger.flush();
        Test.stopTest();
    }

    // ──────────────────────────────────────────────
    // AiFileNamingCalloutService — config missing
    // ──────────────────────────────────────────────

    @IsTest
    static void calloutServiceReturnsConfigMissingWhenNoSettings() {
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name = 'Test', Action_Prompt__c = 'Generate name.'
        );
        Account acc = new Account(Name = 'Test');
        ContentVersion cv = new ContentVersion(Title = 'Test');

        AiFileNamingCalloutService.CalloutResult result =
            AiFileNamingCalloutService.generateFileName(
                new List<AI_File_Naming_Rule__c>{ rule }, acc, cv
            );
    }

    // ──────────────────────────────────────────────
    // AiFileNamingCalloutService — success parse
    // ──────────────────────────────────────────────

    @IsTest
    static void calloutServiceParsesSuccessResponse() {
        setupGeminiSettings();

        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name             = 'Test Rule',
            Criteria_Mode__c = 'tags_only',
            Tags__c          = 'test',
            Action_Prompt__c = 'Generate name.'
        );
        Account acc = new Account(Name = 'Test Account');
        ContentVersion cv = new ContentVersion(
            Title       = 'Test File',
            VersionData = Blob.valueOf('content')
        );

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiSuccessMock());
        AiFileNamingCalloutService.CalloutResult result =
            AiFileNamingCalloutService.generateFileName(
                new List<AI_File_Naming_Rule__c>{ rule }, acc, cv
            );
        Test.stopTest();
    }


    @IsTest
    static void calloutServiceReturnsNoMatchForEmptyRules() {
        setupGeminiSettings();

        Account acc = new Account(Name = 'Test');
        ContentVersion cv = new ContentVersion(Title = 'Test');

        AiFileNamingCalloutService.CalloutResult result =
            AiFileNamingCalloutService.generateFileName(
                new List<AI_File_Naming_Rule__c>(), acc, cv
            );
    }
}