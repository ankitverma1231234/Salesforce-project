@IsTest(SeeAllData=true)
public class FileStorageSendToPortalTest {

    private static Id getEntityStorageId() {
        return [
            SELECT Id
            FROM fra__Entity_Storage__c
            LIMIT 1
        ].Id;
    }

    @IsTest
    static void testAfterInsert() {

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name = 'Insert Test',
            Send_to_Portal__c = true,
            fra__Entity_Storage__c = getEntityStorageId()
        );

        Test.startTest();
        insert fs;
        Test.stopTest();

        System.assertNotEquals(null, fs.Id);
    }

    @IsTest
    static void testEnableSendToPortal() {

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name = 'Update Test',
            Send_to_Portal__c = false,
            fra__Entity_Storage__c = getEntityStorageId()
        );
        insert fs;

        Test.startTest();

        fs.Send_to_Portal__c = true;
        update fs;

        Test.stopTest();

        fs = [
            SELECT Send_to_Portal__c
            FROM fra__File_Storage__c
            WHERE Id = :fs.Id
        ];

        System.assertEquals(true, fs.Send_to_Portal__c);
    }

    @IsTest
    static void testMetadataChangeWhileEnabled() {

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name = 'Original',
            Send_to_Portal__c = true,
            fra__Entity_Storage__c = getEntityStorageId()
        );
        insert fs;

        Test.startTest();

        fs.Name = 'Updated Name';
        update fs;

        Test.stopTest();

        fs = [
            SELECT Name
            FROM fra__File_Storage__c
            WHERE Id = :fs.Id
        ];

        System.assertEquals('Updated Name', fs.Name);
    }

    @IsTest
    static void testDisableSendToPortal() {

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name = 'Delete Flow Test',
            Send_to_Portal__c = true,
            fra__Entity_Storage__c = getEntityStorageId()
        );
        insert fs;

        Test.startTest();

        fs.Send_to_Portal__c = false;
        update fs;

        Test.stopTest();

        fs = [
            SELECT Send_to_Portal__c
            FROM fra__File_Storage__c
            WHERE Id = :fs.Id
        ];

        System.assertEquals(false, fs.Send_to_Portal__c);
    }

    @IsTest
    static void testAiSourceCascadeUpdate() {

        Id entityStorageId = getEntityStorageId();

        Account acc = [SELECT Id FROM Account LIMIT 1];
        String sourceFileId = acc.Id;

        fra__File_Storage__c parentFile = new fra__File_Storage__c(
            Name = 'Parent',
            Send_to_Portal__c = false,
            Fra_AI_Source_File_Id__c = sourceFileId,
            fra__Entity_Storage__c = entityStorageId
        );

        fra__File_Storage__c childFile = new fra__File_Storage__c(
            Name = 'Child',
            Send_to_Portal__c = false,
            Fra_AI_Source_File_Id__c = sourceFileId,
            fra__Entity_Storage__c = entityStorageId
        );

        insert new List<fra__File_Storage__c>{ parentFile, childFile };

        Test.startTest();

        parentFile.Send_to_Portal__c = true;
        update parentFile;

        Test.stopTest();

        childFile = [
            SELECT Id, Send_to_Portal__c
            FROM fra__File_Storage__c
            WHERE Id = :childFile.Id
        ];

        System.assertEquals(
            true,
            childFile.Send_to_Portal__c
        );
    }

    @IsTest
    static void testNoRelevantUpdate() {

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name = 'No Change',
            Send_to_Portal__c = false,
            fra__Entity_Storage__c = getEntityStorageId()
        );
        insert fs;

        Test.startTest();

        update fs;

        Test.stopTest();

        System.assertNotEquals(null, fs.Id);
    }
}