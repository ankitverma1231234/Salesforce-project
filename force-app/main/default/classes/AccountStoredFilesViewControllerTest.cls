@IsTest(SeeAllData=true)
private class AccountStoredFilesViewControllerTest {
    @IsTest
    static void getStoredFilesMapsFieldsAndPreviewUrls() {
        Account testAccount = getExistingAccount();
        Id firstId = syntheticFileStorageId(1);
        Id secondId = syntheticFileStorageId(2);
        SObject htmlLink = syntheticStoredFile(new Map<String, Object>{
            'Id' => firstId,
            'Name' => 'Stored File One',
            'fra__File_Type__c' => 'PDF',
            'fra__File_Size__c' => '10 KB',
            'fra__File_Public_Url__c' => 'https://public.example/one',
            'fra__View_File__c' =>
                '<a href="https://view.example/one?a=1&amp;b=2">View</a>',
            'fra__File_Id__c' => 'drive-one',
            'Send_to_Portal__c' => true,
            'Date_of_Service_Display__c' => '2026-06-05',
            'Source_Type__c' => 'Metriport',
            'Category__c' => 'Clinical',
            'fra__Internal_File_Id__c' => '068000000000001AAA',
            'Related_Summary_File__c' => '068000000000002AAA',
            'LastModifiedDate' =>
                System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
        });
        SObject fallbackLink = syntheticStoredFile(new Map<String, Object>{
            'Id' => secondId,
            'Name' => 'Stored File Two',
            'fra__File_Public_Url__c' => 'https://public.example/two',
            'LastModifiedDate' =>
                System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
        });
        AccountStoredFilesViewController.storedFilesForTest =
            new List<SObject>{ htmlLink, fallbackLink };

        List<AccountStoredFilesViewController.StoredFileRow> rows =
            AccountStoredFilesViewController.getStoredFiles(testAccount.Id);
        Map<Id, AccountStoredFilesViewController.StoredFileRow> rowsById =
            new Map<Id, AccountStoredFilesViewController.StoredFileRow>();
        for (AccountStoredFilesViewController.StoredFileRow row : rows) {
            rowsById.put(row.id, row);
        }

        System.assert(rowsById.containsKey(firstId));
        System.assert(rowsById.containsKey(secondId));
        System.assertEquals(
            'https://view.example/one?a=1&b=2',
            rowsById.get(firstId).viewUrl
        );
        System.assertEquals(
            'https://public.example/two',
            rowsById.get(secondId).viewUrl
        );
        System.assertEquals(true, rowsById.get(firstId).sendToPortal);
       
    }

    @IsTest
    static void updateAndDeleteStoredFilePersistChanges() {
        Account testAccount = getExistingAccount();
        fra__File_Storage__c storedFile = FileStorageApexTestFactory.createFileStorage(
            testAccount,
            'Mutable Stored File',
            new Map<String, Object>{ 'Send_to_Portal__c' => false }
        );

        AccountStoredFilesViewController.updateSendToPortal(storedFile.Id, true);
        System.assertEquals(
            true,
            [SELECT Send_to_Portal__c FROM fra__File_Storage__c WHERE Id = :storedFile.Id]
                .Send_to_Portal__c
        );

        AccountStoredFilesViewController.updateSendToPortal(storedFile.Id, null);
        System.assertEquals(
            false,
            [SELECT Send_to_Portal__c FROM fra__File_Storage__c WHERE Id = :storedFile.Id]
                .Send_to_Portal__c
        );

        AccountStoredFilesViewController.deleteStoredFile(storedFile.Id);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM fra__File_Storage__c WHERE Id = :storedFile.Id]
        );
    }

    @IsTest
    static void controllerRejectsNullAndUnknownIds() {
        assertAuraFailure('getStoredFiles', null);
        assertAuraFailure('updateSendToPortal', null);
        assertAuraFailure('deleteStoredFile', null);

        Id missingId = Id.valueOf('a00000000000001AAA');
        try {
            AccountStoredFilesViewController.deleteStoredFile(missingId);
            System.assert(false, 'Expected missing record exception.');
        } catch (AuraHandledException expected) {
            System.assert(expected.getMessage().contains('Script-thrown exception'));
        }
    }

    private static void assertAuraFailure(String operation, Id recordId) {
        try {
            if (operation == 'getStoredFiles') {
                AccountStoredFilesViewController.getStoredFiles(recordId);
            } else if (operation == 'updateSendToPortal') {
                AccountStoredFilesViewController.updateSendToPortal(recordId, true);
            } else {
                AccountStoredFilesViewController.deleteStoredFile(recordId);
            }
            System.assert(false, 'Expected AuraHandledException for ' + operation);
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }

    private static Account getExistingAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
    }

    private static SObject syntheticStoredFile(Map<String, Object> values) {
        Map<String, Object> payload = new Map<String, Object>{
            'attributes' => new Map<String, Object>{
                'type' => 'fra__File_Storage__c'
            }
        };
        payload.putAll(values);
        return (SObject) JSON.deserialize(
            JSON.serialize(payload),
            SObject.class
        );
    }

    private static Id syntheticFileStorageId(Integer sequence) {
        String suffix = String.valueOf(sequence).leftPad(12, '0');
        return Id.valueOf(
            fra__File_Storage__c.SObjectType.getDescribe().getKeyPrefix() +
            suffix
        );
    }
}