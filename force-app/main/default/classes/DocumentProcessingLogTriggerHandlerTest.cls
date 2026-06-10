@IsTest(SeeAllData=true)
private class DocumentProcessingLogTriggerHandlerTest {
    @IsTest
    static void handleIgnoresNullEmptyAndInsertContexts() {
        DocumentProcessingLogTriggerHandler.handle(null, null);
        DocumentProcessingLogTriggerHandler.handle(
            new List<Document_Processing_Log__c>(),
            new Map<Id, Document_Processing_Log__c>()
        );

        Document_Processing_Log__c inserted =
            new Document_Processing_Log__c(Ready_for_Attachment__c = true);
        DocumentProcessingLogTriggerHandler.handle(
            new List<Document_Processing_Log__c>{ inserted },
            null
        );

        System.assertEquals(
            0,
            Limits.getQueueableJobs(),
            'Insert-like contexts must not enqueue pipeline jobs.'
        );
    }

    @IsTest
    static void handleEnqueuesEachReadyFlagTransitionInPriorityOrder() {
        ContentVersion version = FileStorageApexTestFactory.createFile(
            getExistingAccount(),
            'Trigger Handler',
            'TriggerHandler.pdf',
            'content'
        );
        Document_Processing_Log__c logRecord =
            FileStorageApexTestFactory.createProcessingLog(version.Id, false);

        List<String> fields = new List<String>{
            'Ready_for_Attachment__c',
            'Ready_for_Ai_Naming__c',
            'Ready_for_Ai_Summery__c',
            'Ready_for_Gdrive__c'
        };

        for (String fieldName : fields) {
            Document_Processing_Log__c oldLog = new Document_Processing_Log__c(
                Id = logRecord.Id,
                Content_Version_Id__c = String.valueOf(version.Id)
            );
            Document_Processing_Log__c newLog = oldLog.clone(false, true, false, false);
            newLog.Id = logRecord.Id;
            newLog.put(fieldName, true);

            Integer jobsBefore = Limits.getQueueableJobs();
            DocumentProcessingLogTriggerHandler.handle(
                new List<Document_Processing_Log__c>{ newLog },
                new Map<Id, Document_Processing_Log__c>{ logRecord.Id => oldLog }
            );
            System.assertEquals(
                jobsBefore + 1,
                Limits.getQueueableJobs(),
                'A false-to-true transition should enqueue ' + fieldName
            );
        }
    }

    @IsTest
    static void handleSkipsUnchangedMissingVersionAndMissingOldRows() {
        ContentVersion version = FileStorageApexTestFactory.createFile(
            getExistingAccount(),
            'No Trigger',
            'NoTrigger.pdf',
            'content'
        );
        Document_Processing_Log__c logRecord =
            FileStorageApexTestFactory.createProcessingLog(version.Id, false);

        Document_Processing_Log__c unchanged = new Document_Processing_Log__c(
            Id = logRecord.Id,
            Content_Version_Id__c = String.valueOf(version.Id),
            Ready_for_Attachment__c = true
        );
        Document_Processing_Log__c oldUnchanged = unchanged.clone(false, true, false, false);
        oldUnchanged.Id = logRecord.Id;

        Document_Processing_Log__c missingVersion = new Document_Processing_Log__c(
            Id = logRecord.Id,
            Ready_for_Attachment__c = true
        );

        DocumentProcessingLogTriggerHandler.handle(
            new List<Document_Processing_Log__c>{ unchanged, missingVersion },
            new Map<Id, Document_Processing_Log__c>{ logRecord.Id => oldUnchanged }
        );
        DocumentProcessingLogTriggerHandler.handle(
            new List<Document_Processing_Log__c>{ unchanged },
            new Map<Id, Document_Processing_Log__c>()
        );

        System.assertEquals(0, Limits.getQueueableJobs());
    }

    private static Account getExistingAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
    }
}