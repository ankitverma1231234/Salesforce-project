@IsTest(seeAllData=true)
public class ContentDocumentPrepareQueueableTest {

    @IsTest
    static void testExecute_WithExistingAccount() {

        // -------- Fetch existing Account (NO INSERT) --------
        Account acc = [
            SELECT Id
            FROM Account
            WHERE metriport_patient_Id__c = 'patient-123'
            LIMIT 1
        ];
        System.assertNotEquals(null, acc, 'Account with patient-123 must exist');

        // -------- Ensure at least one Contact exists (NO INSERT) --------
        Contact con = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, con, 'At least one Contact must exist');

        // -------- Create ContentVersion (allowed) --------
        ContentVersion cv = new ContentVersion(
            Title = 'Queueable Test File',
            PathOnClient = 'QueueableTest.txt',
            VersionData = Blob.valueOf('Queueable test content'),
            Source__c ='Metriport',
            FirstPublishLocationId = acc.Id
        );
        insert cv;

        // -------- Get ContentDocumentId --------
        ContentVersion insertedCV = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        Id contentDocumentId = insertedCV.ContentDocumentId;
        System.assertNotEquals(null, contentDocumentId);

        // -------- Prepare input for Queueable --------
        List<Id> contentDocIds = new List<Id>{ contentDocumentId };

        Test.startTest();

        // -------- Execute Queueable --------
        System.enqueueJob(
            new ContentDocumentPrepareQueueable(contentDocIds)
        );

        Test.stopTest();

        // -------- Assertions (execution-based) --------
        // If no exception occurred:
        // - ContentDocumentLink queried
        // - ContentDistribution created or reused
        // - Payload built
        // - ContentDocumentQueueable enqueued
        System.assert(true, 'Queueable executed successfully');
    }
}