@IsTest(seeAllData=true)
private class MetriportDocumentDownloadQueueableTest {

    /* -------------------------------------------------------
       HTTP CALLOUT MOCK
    ------------------------------------------------------- */
    private class MetriportDownloadMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // 1️⃣ First callout → download-url API
            if (req.getEndpoint().contains('/document/download-url')) {
                res.setBody('{"url":"https://example.com/fakefile.pdf"}');
                return res;
            }

            // 2️⃣ Second callout → actual file download
            if (req.getEndpoint().contains('example.com')) {
                res.setBodyAsBlob(Blob.valueOf('Dummy PDF content'));
                return res;
            }

            res.setStatusCode(400);
            return res;
        }
    }

    /* -------------------------------------------------------
       TEST METHOD
    ------------------------------------------------------- */
            public static Id getAccountRecordTypeId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }
    @IsTest
    static void testDocumentDownloadQueueable_success() {

        // -------------------------
        // Test Patient (Account)
        // -------------------------
                Id memberRecordTypeId = getAccountRecordTypeId('PersonAccount');

        Account acc = new Account(
                 FirstName = 'Test',
            LastName ='Patient',
            RecordTypeId = memberRecordTypeId
        );
        insert acc;

        // -------------------------
        // Custom Metadata (Metriport Config)
        // -------------------------
        Metriport_Config__mdt meta = new Metriport_Config__mdt(
            DeveloperName = 'Test_Config',
            MasterLabel = 'Test Config',
            Active__c = true,
            API_Key__c = 'test-api-key',
            Base_URL__c = 'https://api.test.com'
        );
        

        // -------------------------
        // Document Reference
        // -------------------------
        Document_Reference__c docRef = new Document_Reference__c(
            File_Name__c = 'testfile.xml',
            Patient__c = acc.Id,
            Description__c = 'Test Document',
            Date__c = Date.today()
        );
        insert docRef;

        // -------------------------
        // Mock Callouts
        // -------------------------
        Test.setMock(HttpCalloutMock.class, new MetriportDownloadMock());

        // -------------------------
        // Execute Queueable
        // -------------------------
        Test.startTest();
        System.enqueueJob(
            new MetriportDocumentDownloadQueueable(
                new List<Id>{ docRef.Id }
            )
        );
        Test.stopTest();

        // -------------------------
        // Assertions
        // -------------------------
        List<ContentVersion> cvs = [
            SELECT Id, Title, PathOnClient, FirstPublishLocationId
            FROM ContentVersion
            WHERE FirstPublishLocationId = :acc.Id
        ];

        System.assertEquals(
            1,
            cvs.size(),
            'One ContentVersion should be created'
        );


    }

    /* -------------------------------------------------------
       EDGE CASE: EMPTY DOC IDS
    ------------------------------------------------------- */
    @IsTest
    static void testQueueable_withEmptyList() {

        Test.startTest();
        System.enqueueJob(
            new MetriportDocumentDownloadQueueable(
                new List<Id>()
            )
        );
        Test.stopTest();

        // No exception = pass
        System.assert(true);
    }
}