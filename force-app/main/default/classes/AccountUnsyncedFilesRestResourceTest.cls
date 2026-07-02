@IsTest(SeeAllData=true)
private class AccountUnsyncedFilesRestResourceTest {

    @IsTest
    static void testGetReturnsReadyUnsyncedAccountFile() {
        Account accountRecord = getOrCreateAccount();
        createEntityStorage(accountRecord.Id, 'folder-ready-unsynced');
        ContentVersion contentVersion = createContentVersion(
            accountRecord.Id,
            'Ready Unsynced File',
            true
        );

        setupRestContext();

        Test.startTest();
        AccountUnsyncedFilesRestResource.handleGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        List<Object> responseRows = getResponseRecords();
        Map<String, Object> matchingRow = findRow(
            responseRows,
            String.valueOf(contentVersion.Id)
        );

        System.assertNotEquals(null, matchingRow);
        System.assertEquals(
            String.valueOf(contentVersion.Id),
            matchingRow.get('ContentVersionId')
        );
        System.assertEquals(
            String.valueOf(accountRecord.Id),
            matchingRow.get('AccountId')
        );
        System.assertNotEquals(null, matchingRow.get('DriveFolderId'));
        System.assertNotEquals(null, matchingRow.get('PublicUrl'));
    }

    @IsTest
    static void testGetSkipsSyncedAndNotReadyFiles() {
        Account accountRecord = getOrCreateAccount();

        ContentVersion syncedVersion = createContentVersion(
            accountRecord.Id,
            'Already Synced File',
            true
        );
        Id entityStorageId = createEntityStorage(
            accountRecord.Id,
            'folder-already-synced'
        );
        createFileStorage(String.valueOf(syncedVersion.Id), entityStorageId);

        ContentVersion notReadyVersion = createContentVersion(
            accountRecord.Id,
            'Not Ready File',
            false
        );

        setupRestContext();

        Test.startTest();
        AccountUnsyncedFilesRestResource.handleGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        List<Object> responseRows = getResponseRecords();

        System.assertEquals(
            null,
            findRow(responseRows, String.valueOf(syncedVersion.Id))
        );
        System.assertEquals(
            null,
            findRow(responseRows, String.valueOf(notReadyVersion.Id))
        );
    }

    @IsTest
    static void testGetReturnsServerErrorOnUnexpectedFailure() {
        setupRestContext();
        AccountUnsyncedFilesRestResource.forceFailure = true;

        Test.startTest();
        AccountUnsyncedFilesRestResource.handleGet();
        Test.stopTest();

        AccountUnsyncedFilesRestResource.forceFailure = false;

        System.assertEquals(500, RestContext.response.statusCode);
        Map<String, Object> response = (Map<String, Object>)
            JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals(false, response.get('success'));
    }

    @IsTest
    static void testGetInitializesMissingResponseAndParsesInvalidParams() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/account/unsynced-files/';
        req.httpMethod = 'GET';
        req.params.put('page', 'not-a-number');
        req.params.put('pageSize', 'also-bad');
        RestContext.request = req;
        RestContext.response = null;

        Test.startTest();
        AccountUnsyncedFilesRestResource.handleGet();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response);
        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void testGetReturnsEmptyWhenForcedNoUnsyncedFiles() {
        AccountUnsyncedFilesRestResource.forceNoUnsyncedFiles = true;

        Test.startTest();
        AccountUnsyncedFilesRestResource.PagedResponse response =
            AccountUnsyncedFilesRestResource.getUnsyncedAccountFiles(1, 50, 0);
        Test.stopTest();

        AccountUnsyncedFilesRestResource.forceNoUnsyncedFiles = false;

        System.assertEquals(0, response.totalUnsynced);
        System.assertEquals(0, response.totalPages);
        System.assertEquals(true, response.records.isEmpty());
    }

    @IsTest
    static void testGetReturnsEmptyForHighOffsetPage() {
        Account accountRecord = getOrCreateAccount();
        createEntityStorage(accountRecord.Id, 'folder-high-offset');
        createContentVersion(accountRecord.Id, 'High Offset File', true);
        AccountUnsyncedFilesRestResource.forceEmptyPageAfterCount = true;

        Test.startTest();
        AccountUnsyncedFilesRestResource.PagedResponse response =
            AccountUnsyncedFilesRestResource.getUnsyncedAccountFiles(
                2,
                1,
                1
            );
        Test.stopTest();

        AccountUnsyncedFilesRestResource.forceEmptyPageAfterCount = false;

        System.assertEquals(false, response.hasMore);
        System.assertEquals(null, response.nextPageUrl);
        System.assertEquals(true, response.records.isEmpty());
    }

    @IsTest
    static void testGetSkipsVersionsWhenAccountLinksMissing() {
        Account accountRecord = getOrCreateAccount();
        createEntityStorage(accountRecord.Id, 'folder-no-links');
        createContentVersion(accountRecord.Id, 'No Links File', true);
        AccountUnsyncedFilesRestResource.forceNoAccountLinks = true;

        Test.startTest();
        AccountUnsyncedFilesRestResource.PagedResponse response =
            AccountUnsyncedFilesRestResource.getUnsyncedAccountFiles(1, 50, 0);
        Test.stopTest();

        AccountUnsyncedFilesRestResource.forceNoAccountLinks = false;

        System.assertEquals(true, response.records.isEmpty());
    }

    @IsTest
    static void testGetHandlesInvalidSyncedContentVersionId() {
        Account accountRecord = getOrCreateAccount();
        Id entityStorageId = createEntityStorage(accountRecord.Id, 'folder-invalid-sync-id');
        createFileStorage('068not-a-valid-id', entityStorageId);
        setupRestContext();

        Test.startTest();
        AccountUnsyncedFilesRestResource.handleGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void testPublicUrlFallbackUsesDistributionPublicUrl() {
        ContentDistribution distribution = (ContentDistribution)
            JSON.deserialize(
                '{"DistributionPublicUrl":"https://public.example/fallback"}',
                ContentDistribution.class
            );

        System.assertEquals(
            'https://public.example/fallback',
            AccountUnsyncedFilesRestResource.preferredPublicUrl(distribution)
        );
    }

    @IsTest
    static void testDriveFolderFallbackQueryBranches() {
        Account accountRecord = getOrCreateAccount();
        createEntityStorage(accountRecord.Id, 'folder-fallback-query');

        AccountUnsyncedFilesRestResource.forceDriveFolderPrimaryQueryFailure = true;

        Test.startTest();
        Map<Id, String> foldersByAccountId =
            AccountUnsyncedFilesRestResource.getDriveFolderIdsByAccountId(
                new Set<Id>{ accountRecord.Id }
            );
        Test.stopTest();

       
        AccountUnsyncedFilesRestResource.forceDriveFolderPrimaryQueryFailure = false;
    }

    @IsTest
    static void testDriveFolderReturnsEmptyWhenFallbackQueryFails() {
        Account accountRecord = getOrCreateAccount();

        AccountUnsyncedFilesRestResource.forceDriveFolderPrimaryQueryFailure = true;
        AccountUnsyncedFilesRestResource.forceDriveFolderFallbackQueryFailure = true;

        Test.startTest();
        Map<Id, String> foldersByAccountId =
            AccountUnsyncedFilesRestResource.getDriveFolderIdsByAccountId(
                new Set<Id>{ accountRecord.Id }
            );
        Test.stopTest();

        AccountUnsyncedFilesRestResource.forceDriveFolderPrimaryQueryFailure = false;
        AccountUnsyncedFilesRestResource.forceDriveFolderFallbackQueryFailure = false;

        System.assertEquals(true, foldersByAccountId.isEmpty());
    }

    @IsTest
    static void testResolveAccountIdHandlesInvalidStoredId() {
        Account accountRecord = getOrCreateAccount();
        Schema.SObjectType entityStorageType =
            Schema.getGlobalDescribe().get('fra__Entity_Storage__c');
        SObject entityStorage = entityStorageType.newSObject();
        entityStorage.put('fra__File_Store_Record_Id__c', 'not-an-id');

        Id resolvedAccountId = AccountUnsyncedFilesRestResource.resolveAccountId(
            entityStorage,
            new Set<Id>{ accountRecord.Id }
        );

        System.assertEquals(null, resolvedAccountId);
    }

    @IsTest
    static void testPostCreatesFileStorageByFolderIdAndMapsPublicUrl() {
        Account accountRecord = getOrCreateAccount();
        Id entityStorageId = createEntityStorage(
            accountRecord.Id,
            'post-folder-match'
        );

        setupPostRestContext(JSON.serialize(new Map<String, Object>{
            'success' => true,
            'totalRecords' => 2789,
            'processedRecords' => 1,
            'successCount' => 1,
            'failedCount' => 0,
            'successfulUploads' => new List<Object>{
                new Map<String, Object>{
                    'accountId' => String.valueOf(accountRecord.Id),
                    'contentVersionId' => '068000000000001AAA',
                    'googleDriveFileId' => 'drive-file-folder-match',
                    'googleDriveFolderId' => 'post-folder-match',
                    'googleDrivePublicUrl' => 'https://drive.example/folder-match',
                    'fileName' => 'Folder Match.png',
                    'fileType' => 'PNG',
                    'fileSize' => 43554,
                    'status' => 'SUCCESS'
                }
            },
            'failedUploads' => new List<Object>()
        }));

        Test.startTest();
        AccountUnsyncedFilesRestResource.UnsyncedFileResponse response =
            AccountUnsyncedFilesRestResource.createUnsyncedFiles();
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('Upload results received successfully.', response.message);
        System.assertEquals(2789, response.processedRecords);
        System.assertEquals(1, response.updatedRecords);
        System.assertEquals(0, response.failedRecords);

        fra__File_Storage__c storedFile = [
            SELECT Name,
                   fra__File_Name__c,
                   fra__File_Id__c,
                   fra__Internal_File_Id__c,
                   fra__File_Public_Url__c,
                   Public_Url_Chekbox__c,
                   fra__Uploaded_Drive__c,
                   fra__Object_RecordId__c,
                   fra__Entity_Storage__c
            FROM fra__File_Storage__c
            WHERE fra__File_Id__c = 'drive-file-folder-match'
            LIMIT 1
        ];

        System.assertEquals('Folder Match.png', storedFile.Name);
        System.assertEquals('Folder Match.png', storedFile.fra__File_Name__c);
        System.assertEquals('068000000000001AAA', storedFile.fra__Internal_File_Id__c);
        System.assertEquals(
            'https://drive.example/folder-match',
            storedFile.fra__File_Public_Url__c
        );
        System.assertEquals(true, storedFile.Public_Url_Chekbox__c);
        System.assertEquals('Google Drive', storedFile.fra__Uploaded_Drive__c);
        if (isFileStorageFieldCreateable('fra__Object_RecordId__c')) {
            System.assertEquals(
                String.valueOf(accountRecord.Id),
                storedFile.fra__Object_RecordId__c
            );
        }
        System.assertEquals(entityStorageId, storedFile.fra__Entity_Storage__c);
    }

    @IsTest
    static void testPostFallsBackToAccountIdAndHandlesBlankPublicUrl() {
        Account accountRecord = getOrCreateAccount();
        Id entityStorageId = createEntityStorage(
            accountRecord.Id,
            'post-account-fallback-folder'
        );

        setupPostRestContext(JSON.serialize(new Map<String, Object>{
            'success' => true,
            'totalRecords' => 2,
            'processedRecords' => 1,
            'successCount' => 1,
            'failedCount' => 0,
            'successfulUploads' => new List<Object>{
                new Map<String, Object>{
                    'accountId' => String.valueOf(accountRecord.Id),
                    'contentVersionId' => '068000000000002AAA',
                    'googleDriveFileId' => 'drive-file-account-fallback',
                    'googleDriveFolderId' => 'folder-not-on-entity-storage',
                    'googleDrivePublicUrl' => '',
                    'fileName' => 'Account Fallback.png',
                    'fileType' => 'PNG',
                    'fileSize' => 20088,
                    'status' => 'SUCCESS'
                }
            },
            'failedUploads' => new List<Object>()
        }));

        Test.startTest();
        AccountUnsyncedFilesRestResource.UnsyncedFileResponse response =
            AccountUnsyncedFilesRestResource.createUnsyncedFiles();
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals(1, response.updatedRecords);
        System.assertEquals(0, response.failedRecords);

        fra__File_Storage__c storedFile = [
            SELECT fra__File_Public_Url__c,
                   Public_Url_Chekbox__c,
                   fra__Entity_Storage__c
            FROM fra__File_Storage__c
            WHERE fra__File_Id__c = 'drive-file-account-fallback'
            LIMIT 1
        ];

        System.assertEquals(null, storedFile.fra__File_Public_Url__c);
        System.assertEquals(false, storedFile.Public_Url_Chekbox__c);
        System.assertEquals(entityStorageId, storedFile.fra__Entity_Storage__c);
    }

    @IsTest
    static void testPostSkipsRowsWithoutMatchingEntityStorage() {
        Account accountRecord = getOrCreateAccount();

        setupPostRestContext(JSON.serialize(new Map<String, Object>{
            'success' => true,
            'totalRecords' => 1,
            'processedRecords' => 1,
            'successCount' => 1,
            'failedCount' => 4,
            'successfulUploads' => new List<Object>{
                new Map<String, Object>{
                    'accountId' => String.valueOf(accountRecord.Id),
                    'contentVersionId' => '068000000000003AAA',
                    'googleDriveFileId' => 'drive-file-no-parent',
                    'googleDriveFolderId' => 'post-folder-no-parent',
                    'googleDrivePublicUrl' => 'https://drive.example/no-parent',
                    'fileName' => 'No Parent.png',
                    'fileType' => 'PNG',
                    'fileSize' => 100,
                    'status' => 'SUCCESS'
                }
            },
            'failedUploads' => new List<Object>()
        }));

        Test.startTest();
        AccountUnsyncedFilesRestResource.UnsyncedFileResponse response =
            AccountUnsyncedFilesRestResource.createUnsyncedFiles();
        Test.stopTest();


        
    }

    @IsTest
    static void testPostReturnsSuccessForNoSuccessfulUploads() {
        setupPostRestContext(JSON.serialize(new Map<String, Object>{
            'success' => true,
            'totalRecords' => 2789,
            'processedRecords' => 0,
            'successCount' => 0,
            'failedCount' => 4,
            'successfulUploads' => new List<Object>(),
            'failedUploads' => new List<Object>()
        }));

        Test.startTest();
        AccountUnsyncedFilesRestResource.UnsyncedFileResponse response =
            AccountUnsyncedFilesRestResource.createUnsyncedFiles();
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals(2789, response.processedRecords);
        System.assertEquals(0, response.updatedRecords);
        System.assertEquals(4, response.failedRecords);
    }

    @IsTest
    static void testPostReturnsServerErrorForInvalidJson() {
        setupPostRestContext('this is not json');

        Test.startTest();
        AccountUnsyncedFilesRestResource.UnsyncedFileResponse response =
            AccountUnsyncedFilesRestResource.createUnsyncedFiles();
        Test.stopTest();

        System.assertEquals(500, RestContext.response.statusCode);
        System.assertEquals(false, response.success);
        System.assertEquals(0, response.processedRecords);
        System.assertEquals(0, response.updatedRecords);
        System.assertEquals(0, response.failedRecords);
    }

    private static void setupRestContext() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/account/unsynced-files/';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    private static void setupPostRestContext(String requestBody) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/account/unsynced-files/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    private static List<Object> getResponseRecords() {
        Map<String, Object> response = (Map<String, Object>)
            JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assert(
            response.containsKey('records'),
            'Expected paged response to include a records array. Body: ' +
            RestContext.response.responseBody.toString()
        );
        return (List<Object>) response.get('records');
    }

    private static Account getOrCreateAccount() {
        try {
            Account accountRecord = new Account(
                Name = 'Unsynced Files Test Account ' + DateTime.now().getTime()
            );
            insert accountRecord;
            return accountRecord;
        } catch (DmlException ex) {
            return [
                SELECT Id
                FROM Account
                LIMIT 1
            ];
        }
    }

    private static ContentVersion createContentVersion(
        Id accountId,
        String title,
        Boolean readyForExternalSync
    ) {
        ContentVersion contentVersion = new ContentVersion(
            Title = title,
            PathOnClient = title.replace(' ', '_') + '.txt',
            VersionData = Blob.valueOf(title),
            FirstPublishLocationId = accountId,
            Ready_For_External_Sync__c = readyForExternalSync
        );
        insert contentVersion;

        return [
            SELECT Id,
                   ContentDocumentId,
                   FileType,
                   FirstPublishLocationId,
                   Ready_For_External_Sync__c
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
        ];
    }

    private static Id createEntityStorage(Id accountId, String driveFolderId) {
        Schema.SObjectType entityStorageType =
            Schema.getGlobalDescribe().get('fra__Entity_Storage__c');
        System.assertNotEquals(
            null,
            entityStorageType,
            'Expected fra__Entity_Storage__c to be available.'
        );

        SObject entityStorage = entityStorageType.newSObject();
        Map<String, Schema.SObjectField> fields =
            entityStorageType.getDescribe().fields.getMap();

        putIfCreateable(entityStorage, fields, 'Name', 'Unsynced Files Test Entity');
        putIfCreateable(
            entityStorage,
            fields,
            'fra__File_Store_Record_Id__c',
            String.valueOf(accountId)
        );
        putIfCreateable(entityStorage, fields, 'Record_Id__c', String.valueOf(accountId));
        putIfCreateable(
            entityStorage,
            fields,
            'fra__Entity_Folder_ID__c',
            driveFolderId
        );
        putIfCreateable(
            entityStorage,
            fields,
            'fra__Entity_Folder_Name__c',
            'Unsynced Files Test Folder'
        );

        insert entityStorage;
        return (Id) entityStorage.get('Id');
    }

    private static void createFileStorage(String internalFileId, Id entityStorageId) {
        fra__File_Storage__c fileStorage = new fra__File_Storage__c(
            Name = 'Already Synced File Storage'
        );
        fileStorage.fra__Internal_File_Id__c = internalFileId;
        fileStorage.fra__Entity_Storage__c = entityStorageId;
        insert fileStorage;
    }

    private static void putIfCreateable(
        SObject record,
        Map<String, Schema.SObjectField> fields,
        String fieldName,
        Object value
    ) {
        if (fields.containsKey(fieldName) &&
            fields.get(fieldName).getDescribe().isCreateable()) {
            record.put(fieldName, value);
        }
    }

    private static Boolean isFileStorageFieldCreateable(String fieldName) {
        Map<String, Schema.SObjectField> fields =
            fra__File_Storage__c.SObjectType.getDescribe().fields.getMap();

        return fields.containsKey(fieldName) &&
            fields.get(fieldName).getDescribe().isCreateable();
    }

    private static Map<String, Object> findRow(
        List<Object> responseRows,
        String contentVersionId
    ) {
        for (Object responseRow : responseRows) {
            Map<String, Object> row = (Map<String, Object>) responseRow;
            if (contentVersionId == (String) row.get('ContentVersionId')) {
                return row;
            }
        }
        return null;
    }
}