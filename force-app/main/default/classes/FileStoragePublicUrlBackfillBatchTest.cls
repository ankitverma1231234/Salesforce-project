@IsTest(SeeAllData=true)
private class FileStoragePublicUrlBackfillBatchTest {
    private class GoogleDriveMock implements HttpCalloutMock {
        private Boolean failPermission;
        private Boolean omitLink;

        GoogleDriveMock(Boolean failPermission, Boolean omitLink) {
            this.failPermission = failPermission;
            this.omitLink = omitLink;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().contains('/permissions')) {
                response.setStatusCode(failPermission ? 500 : 201);
                response.setBody(failPermission ? '{"error":"denied"}' : '{"id":"permission"}');
                return response;
            }

            response.setStatusCode(200);
            response.setBody(
                omitLink
                    ? '{}'
                    : '{"webViewLink":"https://drive.example/public-file"}'
            );
            return response;
        }
    }

    @IsTest
    static void executeGeneratesPublicUrlAndSkipsIneligibleRows() {
        Account testAccount = FileStorageApexTestFactory.getTestAccount();
        FileStorageApexTestFactory.ensureGoogleDriveConfig();
        fra__File_Storage__c eligible = FileStorageApexTestFactory.createFileStorage(
            testAccount,
            'Eligible Drive File',
            new Map<String, Object>{
                'fra__File_Id__c' => 'drive-file-1',
                'fra__Uploaded_Drive__c' => 'Google Drive'
            }
        );
        fra__File_Storage__c existingUrl = FileStorageApexTestFactory.createFileStorage(
            testAccount,
            'Existing URL',
            new Map<String, Object>{
                'fra__File_Id__c' => 'drive-file-2',
                'fra__Uploaded_Drive__c' => 'Google Drive',
                'fra__File_Public_Url__c' => 'https://already.example/file'
            }
        );
        fra__File_Storage__c blankFileId =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Blank Drive File Id',
                new Map<String, Object>{
                    'fra__Uploaded_Drive__c' => 'Google Drive'
                }
            );
        fra__File_Storage__c wrongDrive =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Wrong Drive',
                new Map<String, Object>{
                    'fra__File_Id__c' => 'wrong-drive-file'
                }
            );

        Test.setMock(HttpCalloutMock.class, new GoogleDriveMock(false, false));
        FileStoragePublicUrlBackfillBatch batchInstance =
            new FileStoragePublicUrlBackfillBatch();
        List<SObject> scope = new List<SObject>();
        scope.addAll([
            SELECT Id, fra__File_Id__c, fra__File_Public_Url__c,
                   fra__Uploaded_Drive__c
            FROM fra__File_Storage__c
            WHERE Id IN :new Set<Id>{
                eligible.Id,
                existingUrl.Id,
                blankFileId.Id,
                wrongDrive.Id
            }
        ]);
        for (SObject scopeRecord : scope) {
            if ((Id) scopeRecord.get('Id') == blankFileId.Id) {
                scopeRecord.put('fra__File_Id__c', null);
                scopeRecord.put('fra__Uploaded_Drive__c', 'Google Drive');
            } else if ((Id) scopeRecord.get('Id') == wrongDrive.Id) {
                scopeRecord.put('fra__Uploaded_Drive__c', 'Other Provider');
            }
        }
        Test.startTest();
        batchInstance.execute(null, scope);
        batchInstance.finish(null);
        Test.stopTest();

        Map<Id, fra__File_Storage__c> storedFiles =
            new Map<Id, fra__File_Storage__c>([
                SELECT fra__File_Public_Url__c
                FROM fra__File_Storage__c
                WHERE Id IN :new Set<Id>{
                    eligible.Id,
                    existingUrl.Id,
                    blankFileId.Id,
                    wrongDrive.Id
                }
            ]);
        System.assertEquals(
            'https://drive.example/public-file',
            storedFiles.get(eligible.Id).fra__File_Public_Url__c
        );
        System.assertEquals(
            'https://already.example/file',
            storedFiles.get(existingUrl.Id).fra__File_Public_Url__c
        );
        System.assertEquals(
            null,
            storedFiles.get(blankFileId.Id).fra__File_Public_Url__c
        );
        System.assertEquals(
            null,
            storedFiles.get(wrongDrive.Id).fra__File_Public_Url__c
        );
    }

    @IsTest
    static void executeHandlesCalloutFailuresAndEmptyScopes() {
        Account testAccount = FileStorageApexTestFactory.getTestAccount();
        FileStorageApexTestFactory.ensureGoogleDriveConfig();
        fra__File_Storage__c storedFile = FileStorageApexTestFactory.createFileStorage(
            testAccount,
            'Failed Drive File',
            new Map<String, Object>{
                'fra__File_Id__c' => 'drive-file-failure',
                'fra__Uploaded_Drive__c' => 'Google Drive'
            }
        );

        FileStoragePublicUrlBackfillBatch batchInstance =
            new FileStoragePublicUrlBackfillBatch();
        batchInstance.execute(null, null);
        batchInstance.execute(null, new List<SObject>());

        Test.setMock(HttpCalloutMock.class, new GoogleDriveMock(true, false));
        List<SObject> scope = new List<SObject>();
        scope.addAll([
            SELECT Id, fra__File_Id__c, fra__File_Public_Url__c,
                   fra__Uploaded_Drive__c
            FROM fra__File_Storage__c
            WHERE Id = :storedFile.Id
        ]);
        Test.startTest();
        batchInstance.execute(null, scope);
        Test.stopTest();

        System.assertEquals(
            null,
            [
                SELECT fra__File_Public_Url__c
                FROM fra__File_Storage__c
                WHERE Id = :storedFile.Id
            ].fra__File_Public_Url__c
        );
    }

    @IsTest
    static void executeSkipsWhenGoogleDriveConfigIsInactive() {
        Account testAccount = FileStorageApexTestFactory.getTestAccount();
        SObject config = FileStorageApexTestFactory.ensureGoogleDriveConfig();
        deactivateGoogleDriveConfig(config);
        fra__File_Storage__c storedFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Inactive Config File',
                new Map<String, Object>{
                    'fra__File_Id__c' => 'inactive-config-file',
                    'fra__Uploaded_Drive__c' => 'Google Drive'
                }
            );
        List<SObject> scope = new List<SObject>();
        scope.addAll([
            SELECT Id, fra__File_Id__c, fra__File_Public_Url__c,
                   fra__Uploaded_Drive__c
            FROM fra__File_Storage__c
            WHERE Id = :storedFile.Id
        ]);

        new FileStoragePublicUrlBackfillBatch().execute(null, scope);

        System.assertEquals(
            null,
            [
                SELECT fra__File_Public_Url__c
                FROM fra__File_Storage__c
                WHERE Id = :storedFile.Id
            ].fra__File_Public_Url__c
        );
    }

    @IsTest
    static void startAndSchedulerEntryPointsAreCovered() {
        FileStorageApexTestFactory.ensureGoogleDriveConfig();
        Test.setMock(HttpCalloutMock.class, new GoogleDriveMock(false, false));
        FileStoragePublicUrlBackfillBatch batchInstance =
            new FileStoragePublicUrlBackfillBatch();
        System.assertNotEquals(null, batchInstance.start(null));
        Set<Id> existingJobIds = new Map<Id, AsyncApexJob>([
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'FileStoragePublicUrlBackfillBatch'
        ]).keySet();

        Test.startTest();
        batchInstance.execute((SchedulableContext) null);
        AsyncApexJob queuedJob = [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'FileStoragePublicUrlBackfillBatch'
            AND Id NOT IN :existingJobIds
            AND Status IN ('Holding', 'Queued', 'Preparing')
            LIMIT 1
        ];
        System.abortJob(queuedJob.Id);
        Test.stopTest();

        System.assertEquals(
            'Aborted',
            [
                SELECT Status
                FROM AsyncApexJob
                WHERE Id = :queuedJob.Id
            ].Status
        );
    }

    private static void deactivateGoogleDriveConfig(SObject config) {
        Map<String, Schema.SObjectField> fields =
            config.getSObjectType().getDescribe().fields.getMap();
        String activeField = fields.containsKey('fra__Active__c')
            ? 'fra__Active__c'
            : 'Active__c';
        config.put(activeField, false);
        update config;
    }
}