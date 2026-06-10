@IsTest
private class MetriportDocumentDownloadQueueableTest {
    private class DownloadMock implements HttpCalloutMock {
        private Integer firstStatus;
        private String firstBody;

        DownloadMock(Integer firstStatus, String firstBody) {
            this.firstStatus = firstStatus;
            this.firstBody = firstBody;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().contains('/document/download-url')) {
                System.assertEquals('GET', request.getMethod());
                System.assertNotEquals(null, request.getHeader('x-api-key'));
                response.setStatusCode(firstStatus);
                response.setBody(firstBody);
                return response;
            }

            response.setStatusCode(200);
            response.setBodyAsBlob(Blob.valueOf('downloaded file bytes'));
            return response;
        }
    }

    private class ThrowingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Simulated timeout');
        }
    }

    @IsTest
    static void queueableDownloadsXmlAsPdfAndCreatesProcessingLog() {
        Account testAccount = FileStorageApexTestFactory.getTestAccount();
        Document_Reference__c documentReference = new Document_Reference__c(
            File_Name__c = 'clinical-document.xml',
            Patient__c = testAccount.Id,
            Description__c = 'Clinical Document',
            Date__c = Date.today(),
            Service_Date_Time__c = System.now(),
            Organization_Name__c = 'Test Organization'
        );
        insert documentReference;
        Test.setMock(
            HttpCalloutMock.class,
            new DownloadMock(200, '{"url":"https://download.example/file"}')
        );

        Test.startTest();
        System.enqueueJob(
            new MetriportDocumentDownloadQueueable(
                new List<Id>{ documentReference.Id }
            )
        );
        Test.stopTest();

        ContentVersion savedVersion = [
            SELECT Id, Title, PathOnClient, FirstPublishLocationId, Source_Type__c,
                   Send_File_to_Portal__c, Organization_Name__c
            FROM ContentVersion
            WHERE FirstPublishLocationId = :testAccount.Id
            AND Title = 'Clinical Document'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('clinical-document.pdf', savedVersion.PathOnClient);
        System.assertEquals('Metriport', savedVersion.Source_Type__c);
        System.assertEquals(true, savedVersion.Send_File_to_Portal__c);
        System.assertEquals('Test Organization', savedVersion.Organization_Name__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c = :String.valueOf(savedVersion.Id)
                AND Is_Active__c = true
                AND Ready_for_Attachment__c = true
            ]
        );
    }

    @IsTest
    static void queueableChainsDocumentsAndPreservesNonXmlName() {
        Account testAccount = FileStorageApexTestFactory.getTestAccount();
        List<Document_Reference__c> documents = new List<Document_Reference__c>{
            new Document_Reference__c(
                File_Name__c = 'first.pdf',
                Patient__c = testAccount.Id,
                Description__c = 'First Download'
            ),
            new Document_Reference__c(
                File_Name__c = 'second.pdf',
                Patient__c = testAccount.Id,
                Description__c = 'Second Download'
            )
        };
        insert documents;
        Test.setMock(
            HttpCalloutMock.class,
            new DownloadMock(200, '{"url":"https://download.example/file"}')
        );

        new MetriportDocumentDownloadQueueable(
            new List<Id>{ documents[0].Id }
        ).execute(null);

        new MetriportDocumentDownloadQueueable(
            new List<Id>{ documents[1].Id }
        ).execute(null);

        List<ContentVersion> versions = [
            SELECT Title, PathOnClient
            FROM ContentVersion
            WHERE FirstPublishLocationId = :testAccount.Id
            AND Title IN ('First Download', 'Second Download')
        ];
        Map<String, ContentVersion> versionsByTitle =
            new Map<String, ContentVersion>();
        for (ContentVersion version : versions) {
            versionsByTitle.put(version.Title, version);
        }

        System.assertEquals(2, versionsByTitle.size());
        System.assertEquals(
            'first.pdf',
            versionsByTitle.get('First Download').PathOnClient
        );
        System.assertEquals(
            'second.pdf',
            versionsByTitle.get('Second Download').PathOnClient
        );
    }

    @IsTest
    static void queueableConvertsUppercaseXmlExtension() {
        Account testAccount = FileStorageApexTestFactory.getTestAccount();
        Document_Reference__c documentReference = new Document_Reference__c(
            File_Name__c = 'UPPERCASE.XML',
            Patient__c = testAccount.Id,
            Description__c = 'Uppercase XML'
        );
        insert documentReference;
        Test.setMock(
            HttpCalloutMock.class,
            new DownloadMock(200, '{"url":"https://download.example/file"}')
        );

        new MetriportDocumentDownloadQueueable(
            new List<Id>{ documentReference.Id }
        ).execute(null);

        System.assertEquals(
            'UPPERCASE.pdf',
            [
                SELECT PathOnClient
                FROM ContentVersion
                WHERE FirstPublishLocationId = :testAccount.Id
                AND Title = 'Uppercase XML'
                LIMIT 1
            ].PathOnClient
        );
    }

    @IsTest
    static void queueableHandlesEmptyMissingBlankAndFailedResponses() {
        Account testAccount = FileStorageApexTestFactory.getTestAccount();
        Document_Reference__c blankName = new Document_Reference__c(
            Patient__c = testAccount.Id,
            Description__c = 'Blank Name'
        );
        Document_Reference__c failedDownload = new Document_Reference__c(
            File_Name__c = 'failed.pdf',
            Patient__c = testAccount.Id,
            Description__c = 'Failed Download'
        );
        insert new List<Document_Reference__c>{ blankName, failedDownload };

        new MetriportDocumentDownloadQueueable(null).execute(null);
        new MetriportDocumentDownloadQueueable(new List<Id>()).execute(null);
        new MetriportDocumentDownloadQueueable(new List<Id>{ null }).execute(null);
        new MetriportDocumentDownloadQueueable(
            new List<Id>{ Id.valueOf('a00000000000001AAA') }
        ).execute(null);
        new MetriportDocumentDownloadQueueable(
            new List<Id>{ blankName.Id }
        ).execute(null);

        Test.setMock(HttpCalloutMock.class, new DownloadMock(500, '{"error":"failed"}'));
        new MetriportDocumentDownloadQueueable(
            new List<Id>{ failedDownload.Id }
        ).execute(null);

        Test.setMock(HttpCalloutMock.class, new ThrowingMock());
        new MetriportDocumentDownloadQueueable(
            new List<Id>{ failedDownload.Id }
        ).execute(null);

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM ContentVersion
                WHERE FirstPublishLocationId = :testAccount.Id
                AND Title IN ('Blank Name', 'Failed Download')
            ]
        );
    }
}