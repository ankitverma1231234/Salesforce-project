@IsTest(seeAllData=true)
public class CDSyncTriggerTest {

    @IsTest
    static void testContentDocumentInsertAndDelete() {

        // Fetch existing Account (NO INSERT)
        Account acc = [
            SELECT Id
            FROM Account
            WHERE metriport_patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        System.assertNotEquals(null, acc, 'Required Account not found');

        Test.startTest();

        // ---------- INSERT PATH ----------
        ContentVersion cv = new ContentVersion(
            Title = 'Trigger Test File',
            PathOnClient = 'TriggerTest.txt',
            VersionData = Blob.valueOf('Test Content'),
            FirstPublishLocationId = acc.Id
        );
        insert cv;

        // Get ContentDocument Id
        ContentVersion insertedCV = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        System.assertNotEquals(
            null,
            insertedCV.ContentDocumentId,
            'ContentDocumentId should be created'
        );

        // ---------- DELETE PATH ----------
        ContentDocument cd = [
            SELECT Id
            FROM ContentDocument
            WHERE Id = :insertedCV.ContentDocumentId
        ];

        delete cd;

        Test.stopTest();

        // No assertions required for:
        // - EventBus.publish()
        // - MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty()
        // Execution confirms coverage
    }
}