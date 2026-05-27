@isTest(SeeAllData=true)
public class ContentDocumentDeleteTriggerTest {

    private static Account getTestAccount() {
        return [
            SELECT Id FROM Account 
            WHERE Metriport_Patient_Id__c = 'patient-123' 
            LIMIT 1
        ];
    }

    // ✅ Covers: Send_File_to_Portal__c = true + Medical Summary + audit insert
    @isTest
    static void testDelete_WithPortalAndMedicalSummary() {
        Account acc = getTestAccount();

        ContentVersion cv = new ContentVersion(
            Title = 'Medical Summary',
            PathOnClient = 'MedicalSummary.pdf',
            VersionData = Blob.valueOf('data'),
            FirstPublishLocationId = acc.Id,
            Send_File_to_Portal__c = true
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        delete [SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
        Test.stopTest();

        // ✅ Validate audit record created
        List<Deleted_Record_Audit__c> audits = [
            SELECT Id, External_Id_Metriport__c 
            FROM Deleted_Record_Audit__c
            WHERE External_Id_Metriport__c = 'Medical Summary'
        ];
        System.assert(!audits.isEmpty(), 'Audit record should be created');
    }

    // ✅ Covers: Send_File_to_Portal__c = false (no delete call)
    @isTest
    static void testDelete_WithoutPortal() {
        Account acc = getTestAccount();

        ContentVersion cv = new ContentVersion(
            Title = 'Normal File',
            PathOnClient = 'Normal.pdf',
            VersionData = Blob.valueOf('data'),
            FirstPublishLocationId = acc.Id,
            Send_File_to_Portal__c = false
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        delete [SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
        Test.stopTest();
    }

    // ✅ Covers: FirstPublishLocationId NOT Account (skips logic)
    @isTest
    static void testDelete_NonAccount() {
        Account acc = getTestAccount();

        Contact con = [
            SELECT Id FROM Contact 
            WHERE AccountId = :acc.Id 
            LIMIT 1
        ];

        ContentVersion cv = new ContentVersion(
            Title = 'Contact File',
            PathOnClient = 'Contact.pdf',
            VersionData = Blob.valueOf('data'),
            FirstPublishLocationId = con.Id,
            Send_File_to_Portal__c = true
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        delete [SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
        Test.stopTest();
    }

    // ✅ Covers: Null FirstPublishLocationId
    @isTest
    static void testDelete_NullLocation() {
        ContentVersion cv = new ContentVersion(
            Title = 'No Location',
            PathOnClient = 'NoLocation.pdf',
            VersionData = Blob.valueOf('data'),
            Send_File_to_Portal__c = true
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        delete [SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
        Test.stopTest();
    }

    // ✅ Covers: BULK + both lists populated
    @isTest
    static void testDelete_BulkRecords() {
        Account acc = getTestAccount();

        List<ContentVersion> versions = new List<ContentVersion>();

        for (Integer i = 0; i < 3; i++) {
            versions.add(new ContentVersion(
                Title = (i == 0 ? 'Medical Summary' : 'Bulk File ' + i),
                PathOnClient = 'Bulk' + i + '.pdf',
                VersionData = Blob.valueOf('data'),
                FirstPublishLocationId = acc.Id,
                Send_File_to_Portal__c = true
            ));
        }

        insert versions;

        List<ContentDocument> docs = [
            SELECT Id FROM ContentDocument 
            WHERE Id IN (
                SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :versions
            )
        ];

        Test.startTest();
        delete docs;
        Test.stopTest();

        // ✅ Ensure at least one audit created
        System.assert(
            [SELECT COUNT() FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = 'Medical Summary'] > 0,
            'Audit records should exist in bulk test'
        );
    }
}