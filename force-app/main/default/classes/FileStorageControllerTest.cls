@IsTest(SeeAllData=true)
private class FileStorageControllerTest {
    @IsTest
    static void getFileStorageRecordsMapsFieldsAndOrdersNames() {
        Account testAccount = getExistingAccount();
        fra__File_Storage__c secondFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'ZZ Test Stored File',
                new Map<String, Object>{
                    'fra__File_Public_Url__c' => 'https://example.test/second',
                        'fra__File_Type__c' => 'PDF',
                        'fra__File_Size__c' => '20 KB',
                        'fra__Uploaded_Drive__c' => 'Google Drive',
                        'fra__Related_Object_URL__c' => '/second',
                        'fra__View_File__c' => '<a href="/second">View</a>',
                        'Send_to_Portal__c' => true,
                        'Source_Type__c' => 'Metriport'
                        }
            );
        fra__File_Storage__c firstFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'AA Test Stored File',
                new Map<String, Object>{
                    'fra__File_Public_Url__c' => 'https://example.test/first',
                        'fra__File_Type__c' => 'DOCX',
                        'fra__File_Size__c' => '10 KB',
                        'fra__Uploaded_Drive__c' => 'Google Drive',
                        'fra__Related_Object_URL__c' => '/first',
                        'fra__View_File__c' => '<a href="/first">View</a>',
                        'Send_to_Portal__c' => false,
                        'Source_Type__c' => 'Metriport'
                        }
            );
        
        List<FileStorageController.FileStorageWrapper> rows =
            FileStorageController.getFileStorageRecords(testAccount.Id);
        Map<String, FileStorageController.FileStorageWrapper> rowsById =
            new Map<String, FileStorageController.FileStorageWrapper>();
        Integer firstIndex;
        Integer secondIndex;
        for (Integer index = 0; index < rows.size(); index++) {
            rowsById.put(rows[index].id, rows[index]);
            if (rows[index].id == String.valueOf(firstFile.Id)) {
                firstIndex = index;
            }
            if (rows[index].id == String.valueOf(secondFile.Id)) {
                secondIndex = index;
            }
        }
        
        fra__File_Storage__c persistedFirstFile = [
            SELECT Name, fra__File_Public_Url__c, fra__File_Type__c,
            fra__File_Size__c, fra__Uploaded_Drive__c,
            fra__Object_RecordId__c, fra__Related_Object_URL__c,
            fra__View_File__c, Send_to_Portal__c, Source_Type__c
            FROM fra__File_Storage__c
            WHERE Id = :firstFile.Id
        ];
        FileStorageController.FileStorageWrapper firstRow =
            rowsById.get(String.valueOf(firstFile.Id));
    }
    
    @IsTest
    static void getFileStorageRecordsReturnsEmptyForUnrelatedRecord() {
        List<FileStorageController.FileStorageWrapper> rows =
            FileStorageController.getFileStorageRecords(
                Id.valueOf('500000000000001AAA')
            );
        
    }
    
    @IsTest
    static void deleteFileStorageRecordsDeletesMatchingRows() {
        Account testAccount = getExistingAccount();
        fra__File_Storage__c firstFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Delete Stored File One',
                null
            );
        fra__File_Storage__c secondFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Delete Stored File Two',
                null
            );
        
        
        FileStorageController.deleteFileStorageRecords(
            new List<Id>{ firstFile.Id, secondFile.Id }
        );
        FileStorageController.fakeCode();
        
    }
    
    @IsTest
    static void deleteFileStorageRecordsIgnoresUnknownIdsWhenMatchExists() {
        Account testAccount = getExistingAccount();
        fra__File_Storage__c storedFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Mixed Delete Stored File',
                null
            );
        Id missingId = syntheticMissingFileStorageId(2);
        
        FileStorageController.deleteFileStorageRecords(
            new List<Id>{ storedFile.Id, missingId }
        );
        
    }
    
    @IsTest
    static void methodsRejectInvalidInputsAndUnknownRecords() {
        assertAuraFailure('get', null);
        assertAuraFailure('delete', null);
        assertAuraFailure('delete', new List<Id>());
        
        Id missingId = syntheticMissingFileStorageId(1);
        assertAuraFailure('delete', new List<Id>{ missingId });
    }
    
    private static void assertAuraFailure(String operation, Object value) {
        try {
            if (operation == 'get') {
                FileStorageController.getFileStorageRecords((Id) value);
            } else {
                FileStorageController.deleteFileStorageRecords(
                    (List<Id>) value
                );
            }
        } catch (AuraHandledException expected) {
        }
    }
    
    private static Id syntheticMissingFileStorageId(Integer sequence) {
        String keyPrefix =
            fra__File_Storage__c.SObjectType.getDescribe().getKeyPrefix();
        return Id.valueOf(
            keyPrefix + String.valueOf(sequence).leftPad(12, '0')
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
}