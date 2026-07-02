@IsTest(SeeAllData=true)
private class FileStorageContentBackfillBatchTest {
    @IsTest
    static void startReturnsQueryLocatorAndEmptyScopeIsSafe() {
        FileStorageContentVersionBackfillBatch batchInstance =
            new FileStorageContentVersionBackfillBatch();

        System.assertNotEquals(null, batchInstance.start(null));
        batchInstance.execute(null, new List<fra__File_Storage__c>());
    }

    @IsTest
    static void executeCopiesContentVersionFieldsAndBuildsRelationships() {
        Account testAccount = getExistingAccount();
        String categoryValue = getSharedActiveCategory();
        ContentVersion summary = FileStorageApexTestFactory.createFile(
            testAccount,
            'Summary',
            'Summary.pdf',
            'summary'
        );
        ContentVersion source = FileStorageApexTestFactory.createFile(
            testAccount,
            'Source',
            'Source.pdf',
            'source'
        );
        update new ContentVersion(
            Id = source.Id,
            Source_Type__c = 'Metriport',
            Category__c = categoryValue,
            Service_Date_Time__c = System.now(),
            Related_File__c = String.valueOf(summary.ContentDocumentId)
        );

        fra__File_Storage__c summaryStorage =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Summary Storage',
                new Map<String, Object>{
                    'fra__Internal_File_Id__c' => String.valueOf(summary.Id)
                }
            );
        fra__File_Storage__c sourceStorage =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Source Storage',
                new Map<String, Object>{
                    'fra__Internal_File_Id__c' => String.valueOf(source.Id)
                }
            );

        List<fra__File_Storage__c> scope = [
            SELECT Id, Name, fra__Internal_File_Id__c, Source_Type__c, Category__c,
                   Service_Date_Time__c, Date_of_Service_Display__c,
                   Document_Type__c, Send_to_Portal__c, Related_Summary_file__c,
                   Fra_AI_Source_File_Id__c, Document_Id__c
            FROM fra__File_Storage__c
            WHERE Id IN :new Set<Id>{ summaryStorage.Id, sourceStorage.Id }
        ];

        FileStorageContentVersionBackfillBatch batchInstance =
            new FileStorageContentVersionBackfillBatch();
        batchInstance.execute(null, scope);

        fra__File_Storage__c updatedSource = [
            SELECT Source_Type__c, Category__c, Service_Date_Time__c,
                   Related_Summary_file__c, Fra_AI_Source_File_Id__c
            FROM fra__File_Storage__c
            WHERE Id = :sourceStorage.Id
        ];
        System.assertEquals('Metriport', updatedSource.Source_Type__c);
        System.assertEquals(categoryValue, updatedSource.Category__c);
        System.assertNotEquals(null, updatedSource.Service_Date_Time__c);
        System.assertEquals(
            String.valueOf(summary.Id),
            updatedSource.Related_Summary_file__c
        );
        System.assertEquals(
            String.valueOf(summaryStorage.Id),
            updatedSource.Fra_AI_Source_File_Id__c
        );
    }

    @IsTest
    static void executeSkipsInvalidAndMissingContentVersions() {
        Account testAccount = getExistingAccount();
        fra__File_Storage__c invalidStorage =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Invalid Internal Id',
                new Map<String, Object>{ 'fra__Internal_File_Id__c' => 'not-an-id' }
            );
        List<fra__File_Storage__c> invalidScope = [
            SELECT Id, Name, fra__Internal_File_Id__c, Source_Type__c, Category__c,
                   Service_Date_Time__c, Date_of_Service_Display__c,
                   Document_Type__c, Send_to_Portal__c, Related_Summary_file__c,
                   Fra_AI_Source_File_Id__c, Document_Id__c
            FROM fra__File_Storage__c
            WHERE Id = :invalidStorage.Id
        ];

        FileStorageContentVersionBackfillBatch batchInstance =
            new FileStorageContentVersionBackfillBatch();
        batchInstance.execute(null, invalidScope);

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM fra__File_Storage__c
                WHERE Id = :invalidStorage.Id
            ]
        );

        fra__File_Storage__c missingStorage =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Missing Version',
                new Map<String, Object>{
                    'fra__Internal_File_Id__c' => '068000000000001AAA'
                }
            );
        List<fra__File_Storage__c> missingScope = [
            SELECT Id, Name, fra__Internal_File_Id__c, Source_Type__c, Category__c,
                   Service_Date_Time__c, Date_of_Service_Display__c,
                   Document_Type__c, Send_to_Portal__c, Related_Summary_file__c,
                   Fra_AI_Source_File_Id__c, Document_Id__c
            FROM fra__File_Storage__c
            WHERE Id = :missingStorage.Id
        ];
        batchInstance.execute(null, missingScope);
        System.assertEquals(
            null,
            [
                SELECT Source_Type__c
                FROM fra__File_Storage__c
                WHERE Id = :missingStorage.Id
            ].Source_Type__c
        );
    }

    private static Account getExistingAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
    }

    private static String getSharedActiveCategory() {
        Set<String> fileStorageValues = new Set<String>();
        for (Schema.PicklistEntry entry :
            fra__File_Storage__c.Category__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                fileStorageValues.add(entry.getValue());
            }
        }

        for (Schema.PicklistEntry entry :
            ContentVersion.Category__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && fileStorageValues.contains(entry.getValue())) {
                return entry.getValue();
            }
        }

        return null;
    }
}