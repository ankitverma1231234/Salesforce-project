@IsTest(SeeAllData=true)
private class GeneratePdfQueueableTest {

    // Mock Success Response
    private class PdfMockSuccess implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/pdf');
            res.setBody('Dummy PDF Content');

            return res;
        }
    }

    // Mock Failure Response
    private class PdfMockFailure implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');

            return res;
        }
    }

    @IsTest
    static void testGeneratePdfSuccess() {

        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Test PDF',
            Status = 'New',
            Origin = 'Web'
        );
        insert c;

        Test.setMock(
            HttpCalloutMock.class,
            new PdfMockSuccess()
        );

        Test.startTest();

        System.enqueueJob(
            new GeneratePdfQueueable(
                c.Id,
                '{"test":"data"}',
                'TestPDF'
            )
        );

        Test.stopTest();

        List<ContentVersion> files = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE FirstPublishLocationId = :c.Id
        ];

        System.assert(
            files.size() > 0,
            'PDF should be attached'
        );
    }

    @IsTest
    static void testGeneratePdfFailure() {

        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Error Test',
            Status = 'New',
            Origin = 'Web'
        );
        insert c;

        Test.setMock(
            HttpCalloutMock.class,
            new PdfMockFailure()
        );

        Test.startTest();

        try {

            new GeneratePdfQueueable(
                c.Id,
                '{"test":"data"}',
                'ErrorPDF'
            ).execute(null);

            System.assert(false,
                'Exception should have been thrown');

        } catch (Exception e) {

            System.assert(
                e.getMessage().contains('PDF generation failed')
            );
        }

        Test.stopTest();
    }
}