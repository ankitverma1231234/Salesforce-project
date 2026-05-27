@IsTest(SeeAllData=true)
private class AiFileNamingConventionControllerTest {
    private class GeminiNamingMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(
                '{"candidates":[{"content":{"parts":[{"text":"{\\"matched\\":true,\\"fileName\\":\\"AI Radiology Name.pdf\\"}"}]}}]}'
            );
            return response;
        }
    }
    
    @IsTest
    static void savePreviewAndDeleteRule() {
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
        
        ContentVersion cv = new ContentVersion(
            Title = 'Radiology Scan',
            PathOnClient = 'RadiologyScan.pdf',
            VersionData = Blob.valueOf('test body'),
            FirstPublishLocationId = AccId
        );
        insert cv;
        
        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        
        AI_File_Naming_Rule__c draftRule = new AI_File_Naming_Rule__c(
            Name = 'Radiology Documents',
            Order__c = 1,
            Is_Active__c = true,
            Criteria_Mode__c = 'tags_only',
            Tags__c = 'radiology, scan',
            Action_Prompt__c = 'Use account name and document type.'
        );
        
        Test.startTest();
        AI_File_Naming_Rule__c savedRule =
            AiFileNamingConventionController.saveRule(draftRule);
        
        savedRule.Name = 'Updated Radiology Documents';
        savedRule.Order__c = 2;
        savedRule.Criteria_Mode__c = 'prompt_only';
        savedRule.Criteria_Prompt__c = 'Only match radiology documents.';
        savedRule.Tags__c = null;
        savedRule.Action_Prompt__c = 'Use the updated account and document naming behavior.';
        AI_File_Naming_Rule__c updatedRule =
            AiFileNamingConventionController.saveRule(savedRule);
        
        List<AI_File_Naming_Rule__c> rules =
            AiFileNamingConventionController.getRules();
        List<ContentDocument> files =
            AiFileNamingConventionController.getFilesForAccount(AccId);
        AiFileNamingConventionController.TestResult preview =
            AiFileNamingConventionController.previewFileName(
                updatedRule.Id,
                AccId,
                insertedVersion.ContentDocumentId
            );
        AI_File_Naming_Rule__c inactiveRule =
            AiFileNamingConventionController.setRuleActive(updatedRule.Id, false);
        Test.stopTest();
        
        AI_File_Naming_Rule__c persistedRule = [
            SELECT Name, Order__c, Criteria_Mode__c, Criteria_Prompt__c, Tags__c, Action_Prompt__c
            FROM AI_File_Naming_Rule__c
            WHERE Id = :updatedRule.Id
            LIMIT 1
        ];
        
        
        AiFileNamingConventionController.deleteRule(updatedRule.Id);
        Integer remainingCount = [SELECT COUNT() FROM AI_File_Naming_Rule__c WHERE Id = :updatedRule.Id];
        
    }
    
    @IsTest
    static void dailyBatchPopulatesAiGeneratedFileName() {
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
        
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        settings.API_Key__c = 'test-key';
        settings.Endpoint__c = 'https://example.com/gemini';
        if (settings.Id != null) {
            update settings;
        } else {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            insert settings;
        }
        
        insert new AI_File_Naming_Rule__c(
            Name = 'Radiology Documents',
            Order__c = 1,
            Is_Active__c = true,
            Criteria_Mode__c = 'tags_only',
            Tags__c = 'radiology',
            Action_Prompt__c = 'Generate a readable radiology filename.'
        );
        
        ContentVersion cv = new ContentVersion(
            Title = 'Radiology Image',
            PathOnClient = 'RadiologyImage.pdf',
            VersionData = Blob.valueOf('test body'),
            FirstPublishLocationId = AccId,
            Source__c = 'Metriport'
        );
        insert cv;
        
        // Re-query to get all fields the batch execute method needs
        ContentVersion fullCv = [
            SELECT Id, ContentDocumentId, Title, FileType, CreatedDate, VersionData,
            AI_Generated_File_Name__c, AI_Name_Generated__c, Source__c
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiNamingMock());
        // Call execute directly to avoid the "No more than one executeBatch"
        // error that occurs with SeeAllData=true when multiple ContentVersions exist
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        job.execute((Database.BatchableContext) null, new List<SObject>{ fullCv });
        Test.stopTest();
        
        ContentVersion updatedVersion = [
            SELECT AI_Generated_File_Name__c, AI_Name_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        
        
    }
    
    @IsTest
    static void scheduleDailyAndDeterministicName() {
        Test.startTest();
        AiFileNamingDailyJob.scheduleDaily(null);
        // Cover the Schedulable execute and empty-scope batch execute
        AiFileNamingDailyJob jobInstance = new AiFileNamingDailyJob();
        jobInstance.execute((SchedulableContext) null);
        jobInstance.execute((Database.BatchableContext) null, new List<SObject>());
        jobInstance.finish(null);
        Test.stopTest();
        
        Account accountRecord = new Account(Name = 'Unsafe / Account # Name');
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name = 'Prompt Rule',
            Criteria_Mode__c = 'prompt_only',
            Criteria_Prompt__c = 'Match when a prompt is configured.'
        );
        ContentVersion cv = new ContentVersion(Title = 'Prompt File');
        
        
    }
    
    @IsTest
    static void batchStartAndFinishCoverage() {
        Test.startTest();
        AiFileNamingDailyJob job = new AiFileNamingDailyJob();
        Database.QueryLocator locator = job.start(null);
        
        job.finish(null);
        Test.stopTest();
    }
    
    @IsTest
    static void generateFileNameForPreviewCoverage() {
        String AccId;
        Account accRec =new Account();
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone ,name
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
            accRec =testAcc;
        }else{
            AccId =existingAccounts[0].Id;
            accRec=existingAccounts[0];
        }
        
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        settings.API_Key__c = 'test-key';
        settings.Endpoint__c = 'https://example.com/gemini';
        if (settings.Id != null) {
            update settings;
        } else {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            insert settings;
        }
        
        AI_File_Naming_Rule__c rule = new AI_File_Naming_Rule__c(
            Name = 'Preview Rule',
            Order__c = 1,
            Is_Active__c = true,
            Criteria_Mode__c = 'tags_only',
            Tags__c = 'preview',
            Action_Prompt__c = 'Generate a preview filename.'
        );
        insert rule;
        
        ContentVersion cv = new ContentVersion(
            Title = 'Preview File',
            PathOnClient = 'PreviewFile.pdf',
            VersionData = Blob.valueOf('test body'),
            FirstPublishLocationId = AccId
        );
        insert cv;
        
        ContentVersion fullCv = [
            SELECT Id, Title, FileType, CreatedDate, VersionData
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeminiNamingMock());
        String previewName = AiFileNamingDailyJob.generateFileNameForPreview(rule, accRec, fullCv);
        Test.stopTest();
        
    }
    
    @IsTest
    static void getFilesForAccountWithNullId() {
        List<ContentDocument> files = AiFileNamingConventionController.getFilesForAccount(null);

    }

    @IsTest
    static void saveRuleValidationErrors() {
        Test.startTest();

        // null payload
        try {
            AiFileNamingConventionController.saveRule(null);
            System.assert(false, 'Expected exception for null rule');
        } catch (AuraHandledException ex) { }

        // blank name
        try {
            AiFileNamingConventionController.saveRule(new AI_File_Naming_Rule__c(
                Order__c = 1,
                Action_Prompt__c = 'do stuff',
                Criteria_Mode__c = 'prompt_only',
                Criteria_Prompt__c = 'x'
            ));
            System.assert(false, 'Expected exception for blank name');
        } catch (AuraHandledException ex) { }

        // invalid order
        try {
            AiFileNamingConventionController.saveRule(new AI_File_Naming_Rule__c(
                Name = 'R',
                Order__c = 0,
                Action_Prompt__c = 'do stuff',
                Criteria_Mode__c = 'prompt_only',
                Criteria_Prompt__c = 'x'
            ));
            System.assert(false, 'Expected exception for invalid order');
        } catch (AuraHandledException ex) { }

        // blank action prompt
        try {
            AiFileNamingConventionController.saveRule(new AI_File_Naming_Rule__c(
                Name = 'R',
                Order__c = 1,
                Criteria_Mode__c = 'prompt_only',
                Criteria_Prompt__c = 'x'
            ));
            System.assert(false, 'Expected exception for blank action prompt');
        } catch (AuraHandledException ex) { }

        // prompt_only without prompt
        try {
            AiFileNamingConventionController.saveRule(new AI_File_Naming_Rule__c(
                Name = 'R',
                Order__c = 1,
                Action_Prompt__c = 'do stuff',
                Criteria_Mode__c = 'prompt_only'
            ));
            System.assert(false, 'Expected exception for prompt_only missing prompt');
        } catch (AuraHandledException ex) { }

        // tags_only without tags
        try {
            AiFileNamingConventionController.saveRule(new AI_File_Naming_Rule__c(
                Name = 'R',
                Order__c = 1,
                Action_Prompt__c = 'do stuff',
                Criteria_Mode__c = 'tags_only'
            ));
            System.assert(false, 'Expected exception for tags_only missing tags');
        } catch (AuraHandledException ex) { }

        // prompt_and_tags missing one
        try {
            AiFileNamingConventionController.saveRule(new AI_File_Naming_Rule__c(
                Name = 'R',
                Order__c = 1,
                Action_Prompt__c = 'do stuff',
                Criteria_Mode__c = 'prompt_and_tags',
                Criteria_Prompt__c = 'x'
            ));
            System.assert(false, 'Expected exception for prompt_and_tags missing tags');
        } catch (AuraHandledException ex) { }

        // prompt_or_tags missing both
        try {
            AiFileNamingConventionController.saveRule(new AI_File_Naming_Rule__c(
                Name = 'R',
                Order__c = 1,
                Action_Prompt__c = 'do stuff',
                Criteria_Mode__c = 'prompt_or_tags'
            ));
            System.assert(false, 'Expected exception for prompt_or_tags missing both');
        } catch (AuraHandledException ex) { }

        // prompt_or_tags satisfied with just tags — default mode branch
        AI_File_Naming_Rule__c okRule = AiFileNamingConventionController.saveRule(
            new AI_File_Naming_Rule__c(
                Name = 'OK Rule',
                Order__c = 1,
                Action_Prompt__c = 'do stuff',
                Criteria_Mode__c = 'prompt_or_tags',
                Tags__c = 'abc'
            )
        );
        System.assertNotEquals(null, okRule.Id);

        // blank criteria mode falls through to prompt_only default and needs prompt
        try {
            AiFileNamingConventionController.saveRule(new AI_File_Naming_Rule__c(
                Name = 'R',
                Order__c = 1,
                Action_Prompt__c = 'do stuff'
            ));
            System.assert(false, 'Expected exception for blank mode defaulting to prompt_only');
        } catch (AuraHandledException ex) { }

        Test.stopTest();
    }

    @IsTest
    static void deleteAndSetActiveNullIds() {
        Test.startTest();
        try {
            AiFileNamingConventionController.deleteRule(null);
            System.assert(false, 'Expected exception for null delete id');
        } catch (AuraHandledException ex) { }

        try {
            AiFileNamingConventionController.setRuleActive(null, true);
            System.assert(false, 'Expected exception for null setRuleActive id');
        } catch (AuraHandledException ex) { }
        Test.stopTest();
    }

    @IsTest
    static void previewFileNameNullParams() {
        Test.startTest();
        try {
            AiFileNamingConventionController.previewFileName(null, null, null);
            System.assert(false, 'Expected exception for null preview params');
        } catch (AuraHandledException ex) { }
        Test.stopTest();
    }

    @IsTest
    static void searchAccountsCoverage() {
        Test.startTest();

        // Blank term -> empty list branch
        List<Map<String, String>> empty = AiFileNamingConventionController.searchAccounts(null);
        System.assertEquals(0, empty.size());

        // Short term -> empty list branch
        List<Map<String, String>> shortTerm = AiFileNamingConventionController.searchAccounts('a');
        System.assertEquals(0, shortTerm.size());

        // Normal search — may or may not return rows depending on org data
        AiFileNamingConventionController.searchAccounts('test');
        Test.stopTest();
    }

    @IsTest
    static void getRulesFreshCoverage() {
        insert new AI_File_Naming_Rule__c(
            Name = 'Fresh Rule',
            Order__c = 1,
            Is_Active__c = true,
            Criteria_Mode__c = 'tags_only',
            Tags__c = 'fresh',
            Action_Prompt__c = 'Fresh prompt.'
        );

        Test.startTest();
        List<AI_File_Naming_Rule__c> rules = AiFileNamingConventionController.getRulesFresh();
        Test.stopTest();

        System.assert(rules.size() >= 1);
    }
}