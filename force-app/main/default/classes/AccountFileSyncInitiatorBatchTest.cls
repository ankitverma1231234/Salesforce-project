@IsTest(SeeAllData=true)
private class AccountFileSyncInitiatorBatchTest {
    private static Integer mockExecutions = 0;
    private static Id mockReceivedJobId;
    private static String mockReceivedQuery;

    private static Account getExistingTestAccount() {
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    private static void setEligibility(
        ContentVersion version,
        Boolean isEligible
    ) {
        update new ContentVersion(
            Id = version.Id,
            Source_Type__c = 'Metriport',
            Is_AI_Summary_Generated__c = isEligible,
            AI_Name_Generated__c = isEligible
        );
    }

    private class MockFileSyncExecutor
        implements AccountFileSyncInitiatorBatch.FileSyncExecutor {

        public Id execute(Id jobId, String contentDocumentQuery) {
            mockExecutions++;
            mockReceivedJobId = jobId;
            mockReceivedQuery = contentDocumentQuery;
            return jobId;
        }
    }

    @IsTest
    static void executeFiltersStoredVersionsAndFinishStartsOneSync() {
        Account testAccount = getExistingTestAccount();
        if (testAccount == null) {
            System.debug(
                'Skipping test because no Account exists with ' +
                'Metriport_Patient_Id__c = patient-123.'
            );
            return;
        }
        ContentVersion unsyncedVersion = FileStorageApexTestFactory.createFile(
            testAccount,
            'Initiator Unsynced',
            'InitiatorUnsynced.pdf',
            'unsynced'
        );
        ContentVersion syncedVersion = FileStorageApexTestFactory.createFile(
            testAccount,
            'Initiator Synced',
            'InitiatorSynced.pdf',
            'synced'
        );
        ContentVersion ineligibleVersion =
            FileStorageApexTestFactory.createFile(
                testAccount,
                'Initiator Not AI Summary',
                'InitiatorNotAiSummary.pdf',
                'not eligible'
            );
        setEligibility(unsyncedVersion, true);
        setEligibility(syncedVersion, true);
        setEligibility(ineligibleVersion, false);
        FileStorageApexTestFactory.createFileStorage(
            testAccount,
            'Initiator Synced.pdf',
            new Map<String, Object>{
                'fra__Internal_File_Id__c' => String.valueOf(syncedVersion.Id)
            }
        );

        mockExecutions = 0;
        mockReceivedJobId = null;
        mockReceivedQuery = null;
        AccountFileSyncInitiatorBatch.syncExecutor =
            new MockFileSyncExecutor();

        AccountFileSyncInitiatorBatch batch =
            new AccountFileSyncInitiatorBatch();
        batch.execute(null, new List<Account>{ testAccount });

        System.assertEquals(
            true,
            batch.candidateVersionToDocument.containsKey(unsyncedVersion.Id)
        );
        System.assertEquals(
            false,
            batch.candidateVersionToDocument.containsKey(syncedVersion.Id)
        );
     

        batch.finish(null);

        System.assertEquals(1, mockExecutions);
        System.assertNotEquals(null, mockReceivedJobId);
        System.assert(
            mockReceivedQuery.contains(
                String.valueOf(unsyncedVersion.ContentDocumentId)
            )
        );
        System.assertEquals(1, batch.totalSyncJobsCreated);
        System.assertEquals(1, batch.totalFileSyncBatchExecutions);
    }

    @IsTest
    static void finishSkipsWhenCandidateBecomesSynced() {
        Account testAccount = getExistingTestAccount();
        if (testAccount == null) {
            System.debug(
                'Skipping test because no Account exists with ' +
                'Metriport_Patient_Id__c = patient-123.'
            );
            return;
        }
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Initiator Race Check',
            'InitiatorRaceCheck.pdf',
            'content'
        );

        AccountFileSyncInitiatorBatch batch =
            new AccountFileSyncInitiatorBatch();
        batch.candidateVersionToDocument.put(
            version.Id,
            version.ContentDocumentId
        );

        FileStorageApexTestFactory.createFileStorage(
            testAccount,
            'Initiator Race Check.pdf',
            new Map<String, Object>{
                'fra__Internal_File_Id__c' => String.valueOf(version.Id)
            }
        );

        mockExecutions = 0;
        AccountFileSyncInitiatorBatch.syncExecutor =
            new MockFileSyncExecutor();
        Integer jobsBefore = [SELECT COUNT() FROM fra__File_Sync_Job__c];

        batch.finish(null);

        System.assertEquals(0, mockExecutions);
        System.assertEquals(
            jobsBefore,
            [SELECT COUNT() FROM fra__File_Sync_Job__c]
        );
        System.assertEquals(0, batch.totalSyncJobsCreated);
    }

    @IsTest
    static void emptyScopesAndStartAreSafe() {
        AccountFileSyncInitiatorBatch batch =
            new AccountFileSyncInitiatorBatch();

        System.assertNotEquals(null, batch.start(null));
        batch.execute(null, null);
        batch.execute(null, new List<Account>());
        batch.finish(null);

        System.assertEquals(0, batch.totalAccountsProcessed);
        System.assertEquals(0, batch.totalSyncJobsCreated);
    }

    @IsTest
    static void schedulableEntryPointQueuesInitiatorBatch() {
        Set<Id> existingJobIds = new Map<Id, AsyncApexJob>([
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AccountFileSyncInitiatorBatch'
        ]).keySet();

        Test.startTest();
        new AccountFileSyncInitiatorBatch().execute(
            (SchedulableContext) null
        );
        AsyncApexJob queuedJob = [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AccountFileSyncInitiatorBatch'
            AND Id NOT IN :existingJobIds
            AND Status IN ('Holding', 'Queued', 'Preparing')
            LIMIT 1
        ];
        System.abortJob(queuedJob.Id);
        Test.stopTest();
    }
}