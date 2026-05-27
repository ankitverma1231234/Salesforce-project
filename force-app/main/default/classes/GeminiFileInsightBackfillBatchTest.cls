@isTest(SeeAllData=true)
private class GeminiFileInsightBackfillBatchTest {

    @isTest
    static void testExecuteAccountLinkedFile() {
        Account acc = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        ContentVersion cv = new ContentVersion(
            Title = 'Account Linked Doc',
            PathOnClient = 'AccountDoc.pdf',
            VersionData = Blob.valueOf('PDF content here')
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId, Title, FileType FROM ContentVersion WHERE Id = :cv.Id];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        Test.startTest();
        GeminiFileInsightBackfillBatch batch = new GeminiFileInsightBackfillBatch(true, true);

        // Cover start
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql, 'QueryLocator should not be null');

        // Cover execute — Account linked, callout fails in test = hits catch block
        batch.execute(null, new List<ContentVersion>{ cv });

        // Cover finish with failures
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(1, batch.totalProcessed);
        System.assertEquals(1, batch.totalFailed);
        System.assertEquals(0, batch.totalSkipped);
    }

    @isTest
    static void testExecuteNonAccountLinkedSkipped() {
        ContentVersion cv = new ContentVersion(
            Title = 'Non Account Doc',
            PathOnClient = 'NonAccount.txt',
            VersionData = Blob.valueOf('Not linked to account')
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId, Title, FileType FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        GeminiFileInsightBackfillBatch batch = new GeminiFileInsightBackfillBatch(false, false);

        batch.execute(null, new List<ContentVersion>{ cv });

        // Cover finish with zero failures but records processed
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(1, batch.totalProcessed);
        System.assertEquals(1, batch.totalSkipped);
        System.assertEquals(0, batch.totalSuccess);
        System.assertEquals(0, batch.totalFailed);
    }

    @isTest
    static void testFinishZeroProcessed() {
        Test.startTest();
        GeminiFileInsightBackfillBatch batch = new GeminiFileInsightBackfillBatch(null, null);

        // Cover finish with zero processed — hits the "No records were processed" warning
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(0, batch.totalProcessed);
    }
}