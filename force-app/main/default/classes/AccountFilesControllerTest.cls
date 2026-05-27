@IsTest(SeeAllData=true)
public class AccountFilesControllerTest {

    @IsTest
    static void testWithExistingData() {

        Account testAcc;

        // Try to get existing Person Account
        List<Account> existingAccounts = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        if (!existingAccounts.isEmpty()) {
            testAcc = existingAccounts[0];
        } 
        else {

            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount')
                .getRecordTypeId();

            testAcc = new Account(
                FirstName = 'Test',
                LastName = 'Person',
                RecordTypeId = personAccountRT,
                PersonEmail = 'test@test.com',
                PersonMobilePhone = '9999999999'
            );
            insert testAcc;
        }

        // Create File
        ContentVersion cv = new ContentVersion(
            Title = 'TestFile',
            PathOnClient = 'TestFile.pdf',
            VersionData = Blob.valueOf('Test File Body')
        );

        insert cv;

        // Query ContentDocumentId
        ContentVersion insertedCV = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        // Link File to Account
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = insertedCV.ContentDocumentId,
            LinkedEntityId = testAcc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        Test.startTest();

        // Test getAccountFiles
        List<AccountFilesController.FileWrapper> result =
            AccountFilesController.getAccountFiles(testAcc.Id);

        System.assert(result != null);

        // Test deleteFiles
        List<Id> idsToDelete = new List<Id>{ insertedCV.ContentDocumentId };

        AccountFilesController.deleteFiles(idsToDelete);

        Test.stopTest();
    }
}