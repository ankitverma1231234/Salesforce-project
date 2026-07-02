@IsTest
private class UpdateFileStoragePublicUrlCBBatchTest {

    @IsTest
    static void testBatchUpdatesOnlyRecordsWithPublicUrl() {
        // Create parent Entity Storage record.
        fra__Entity_Storage__c entityStorage = new fra__Entity_Storage__c(
            
            fra__Entity_Folder_ID__c = 'test-folder-id',
            fra__Entity_Folder_Name__c = 'Test Folder'
        );
        insert entityStorage;

        // Child record should be updated.
        fra__File_Storage__c recordWithUrl = new fra__File_Storage__c(
            fra__Entity_Storage__c = entityStorage.Id,
            fra__File_Public_Url__c = 'https://example.com/file1',
            Public_Url_Chekbox__c = false
        );

        // Child record should not be updated because URL is blank.
        fra__File_Storage__c recordWithoutUrl = new fra__File_Storage__c(
            fra__Entity_Storage__c = entityStorage.Id,
            fra__File_Public_Url__c = null,
            Public_Url_Chekbox__c = false
        );

        // Child record should be ignored by WHERE Public_Url_Chekbox__c = false.
        fra__File_Storage__c alreadyCheckedRecord = new fra__File_Storage__c(
            fra__Entity_Storage__c = entityStorage.Id,
            fra__File_Public_Url__c = 'https://example.com/file2',
            Public_Url_Chekbox__c = true
        );

        insert new List<fra__File_Storage__c>{
            recordWithUrl,
            recordWithoutUrl,
            alreadyCheckedRecord
        };

        Test.startTest();
        Database.executeBatch(new UpdateFileStoragePublicUrlCheckboxBatch(), 200);
        Test.stopTest();

        Map<Id, fra__File_Storage__c> resultMap = new Map<Id, fra__File_Storage__c>([
            SELECT Id, fra__File_Public_Url__c, Public_Url_Chekbox__c
            FROM fra__File_Storage__c
            WHERE Id IN :new List<Id>{
                recordWithUrl.Id,
                recordWithoutUrl.Id,
                alreadyCheckedRecord.Id
            }
        ]);

        System.assertEquals(true, resultMap.get(recordWithUrl.Id).Public_Url_Chekbox__c);
        System.assertEquals(false, resultMap.get(recordWithoutUrl.Id).Public_Url_Chekbox__c);
        System.assertEquals(true, resultMap.get(alreadyCheckedRecord.Id).Public_Url_Chekbox__c);
    }
}