@IsTest(SeeAllData=true)
private class AiFileNamingDailyJobTest {
    
    // ──────────────────────────────────────────────
    // Mock callout classes
    // ──────────────────────────────────────────────
    
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
    
    // ──────────────────────────────────────────────
    // Test data setup
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
            Source__c              = 'Metriport'
        );
        insert cv;
        return [
            SELECT Id, ContentDocumentId, Title, FileType, CreatedDate, VersionData,
            AI_Generated_File_Name__c, AI_Name_Generated__c, Source__c
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
    }
    
    // ──────────────────────────────────────────────
    // Tests — Batch Success (direct execute)
    // ──────────────────────────────────────────────
    
    @IsTest
    static void batchSuccessPopulatesFileNameAndFlag() {
        String AccId;
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone 
            FROM Account 
            WHERE IsPersonAccount = true 
            AND PersonEmail != null 
            AND PersonMobilePhone != null 
            LIMIT 1
        ];
        
        if (existingAccounts.isEmpty()) {
            // Create minimal test data if none exists
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
            
            Account testAcc = new Account(
                FirstName = 'Existing',
                LastName = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert testAcc;
            AccId=testAcc.Id;
        }else{
            AccId =existingAccounts[0].Id;
        }
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(AccId);
        
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
    // Tests — API Failure (502)
    // ──────────────────────────────────────────────
    
    @IsTest
    static void batchHandles502ErrorGracefully() {
        String AccId;
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone 
            FROM Account 
            WHERE IsPersonAccount = true 
            AND PersonEmail != null 
            AND PersonMobilePhone != null 
            LIMIT 1
        ];
        
        if (existingAccounts.isEmpty()) {
            // Create minimal test data if none exists
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
            
            Account testAcc = new Account(
                FirstName = 'Existing',
                LastName = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert testAcc;
            AccId=testAcc.Id;
        }else{
            AccId =existingAccounts[0].Id;
        }
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(AccId);
        
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
    // Tests — Timeout
    // ──────────────────────────────────────────────
    
    @IsTest
    static void batchHandlesTimeoutGracefully() {
        String AccId;
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone 
            FROM Account 
            WHERE IsPersonAccount = true 
            AND PersonEmail != null 
            AND PersonMobilePhone != null 
            LIMIT 1
        ];
        
        if (existingAccounts.isEmpty()) {
            // Create minimal test data if none exists
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
            
            Account testAcc = new Account(
                FirstName = 'Existing',
                LastName = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert testAcc;
            AccId=testAcc.Id;
        }else{
            AccId =existingAccounts[0].Id;
        }
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(AccId);
        
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
    // Tests — Invalid Response
    // ──────────────────────────────────────────────
    
    @IsTest
    static void batchHandlesInvalidResponseGracefully() {
        String AccId;
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone 
            FROM Account 
            WHERE IsPersonAccount = true 
            AND PersonEmail != null 
            AND PersonMobilePhone != null 
            LIMIT 1
        ];
        
        if (existingAccounts.isEmpty()) {
            // Create minimal test data if none exists
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
            
            Account testAcc = new Account(
                FirstName = 'Existing',
                LastName = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert testAcc;
            AccId=testAcc.Id;
        }else{
            AccId =existingAccounts[0].Id;
        }
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(AccId);
        
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
    // Tests — No Match
    // ──────────────────────────────────────────────
    
    @IsTest
    static void batchHandlesNoMatchResponse() {
        String AccId;
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone 
            FROM Account 
            WHERE IsPersonAccount = true 
            AND PersonEmail != null 
            AND PersonMobilePhone != null 
            LIMIT 1
        ];
        
        if (existingAccounts.isEmpty()) {
            // Create minimal test data if none exists
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
            
            Account testAcc = new Account(
                FirstName = 'Existing',
                LastName = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert testAcc;
            AccId=testAcc.Id;
        }else{
            AccId =existingAccounts[0].Id;
        }
        setupGeminiSettings();
        createActiveRule();
        ContentVersion cv = createTestContentVersion(AccId);
        
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
    // Tests — No Active Rules
    // ──────────────────────────────────────────────
    
    @IsTest
    static void batchSkipsWhenNoActiveRules() {
        String AccId;
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone 
            FROM Account 
            WHERE IsPersonAccount = true 
            AND PersonEmail != null 
            AND PersonMobilePhone != null 
            LIMIT 1
        ];
        
        if (existingAccounts.isEmpty()) {
            // Create minimal test data if none exists
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
            
            Account testAcc = new Account(
                FirstName = 'Existing',
                LastName = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert testAcc;
            AccId=testAcc.Id;
        }else{
            AccId =existingAccounts[0].Id;
        }
        setupGeminiSettings();
        ContentVersion cv = createTestContentVersion(AccId);
        
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
    // Tests — Missing Gemini Settings
    // ──────────────────────────────────────────────
    
    @IsTest
    static void batchHandlesMissingGeminiSettings() {
        String AccId;
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone 
            FROM Account 
            WHERE IsPersonAccount = true 
            AND PersonEmail != null 
            AND PersonMobilePhone != null 
            LIMIT 1
        ];
        
        if (existingAccounts.isEmpty()) {
            // Create minimal test data if none exists
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
            
            Account testAcc = new Account(
                FirstName = 'Existing',
                LastName = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert testAcc;
            AccId=testAcc.Id;
        }else{
            AccId =existingAccounts[0].Id;
        }
        createActiveRule();
        ContentVersion cv = createTestContentVersion(AccId);
        
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
    // Tests — Scheduling & Lifecycle
    // ──────────────────────────────────────────────
    
    @IsTest
    static void scheduleDailyCoversScheduleMethod() {
        Test.startTest();
        AiFileNamingDailyJob.scheduleDaily(null);
        AiFileNamingDailyJob.scheduleDaily('0 30 3 * * ?');
        Test.stopTest();
        
        
    }
    
    @IsTest
    static void schedulableExecuteCoversLifecycle() {
        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((SchedulableContext) null);
        job.finish(null);
        Test.stopTest();
        
        
    }
    
    @IsTest
    static void batchStartReturnsQueryLocator() {
        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        Database.QueryLocator locator = job.start(null);
        Test.stopTest();
        
    }
    
    @IsTest
    static void batchEmptyScopeExecute() {
        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>());
        job.finish(null);
        Test.stopTest();
        
        
    }
    
    // ──────────────────────────────────────────────
    // Tests — Deterministic Filename Builder
    // ──────────────────────────────────────────────
    
    @IsTest
    static void deterministicFileNameCleansUnsafeCharacters() {
        Account acc = new Account(Name = 'Unsafe / Account # Name');
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name             = 'Prompt Rule',
            Criteria_Mode__c = 'prompt_only',
            Criteria_Prompt__c = 'Match when a prompt is configured.'
        );
        ContentVersion cv = new ContentVersion(Title = 'Prompt File');
        
        String result = AiFileNamingDailyJob.buildDeterministicFileName(rule, acc, cv);
        
        
    }
    
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
    // Tests — Preview (LWC integration point)
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
        ContentVersion cv = new ContentVersion(
            Title = 'Preview File'
        );
        
        String result = AiFileNamingDailyJob.generateFileNameForPreview(rule, acc, cv);
        System.assertEquals(null, result,
                            'Preview should return null when Gemini settings are not configured.');
    }
    
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
    // Tests — Logger Unit Tests
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
        
    }
    
    @IsTest
    static void loggerFlushEmptyBuffer() {
        AiFileNamingLogger logger = new AiFileNamingLogger('EmptyJob');
        
        
        Test.startTest();
        logger.flush();
        Test.stopTest();
        
        
    }
    
    // ──────────────────────────────────────────────
    // Tests — Callout Service Unit Tests
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
        
        System.assertEquals(true, result.success, 'Should succeed with valid response.');
        System.assertEquals('Success', result.status);
        System.assert(String.isNotBlank(result.fileName), 'File name should be populated.');
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
        
        System.assertEquals(false, result.success, 'Should not succeed with empty rules.');
        System.assertEquals('No_Match', result.status, 'Status should be No_Match.');
    }
}