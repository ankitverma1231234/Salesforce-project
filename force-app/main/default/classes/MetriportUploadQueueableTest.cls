@IsTest(SeeAllData=true)
private class MetriportUploadQueueableTest {

    private class MetriportMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();

            // Document Reference API
            if(req.getMethod() == 'POST') {

                res.setStatusCode(201);
                res.setBody(
                    '{"uploadUrl":"https://dummy-upload-url.com"}'
                );

                return res;
            }

            // File Upload API
            if(req.getMethod() == 'PUT') {

                res.setStatusCode(200);
                res.setBody('');

                return res;
            }

            res.setStatusCode(500);
            res.setBody('Unexpected Request');

            return res;
        }
    }

    @IsTest
    static void testMetriportUploadQueueable() {

        Account acc = [
            SELECT Id, Name
            FROM Account
            LIMIT 1
        ];

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Metriport Test',
            Status = 'New',
            Origin = 'Web'
        );
        insert c;

        Test.setMock(
            HttpCalloutMock.class,
            new MetriportMock()
        );

        Blob pdfBlob = Blob.valueOf('Dummy PDF Content');

        Test.startTest();

        System.enqueueJob(
            new MetriportUploadQueueable(
                'PATIENT123',
                acc.Name,
                pdfBlob,
                'ClinicalSummary.pdf',
                'pdf',
                'Clinical Summary',
                '34133-9',
                'Summarization of Episode Note',
                'Hospital',
                String.valueOf(Date.today()),
                c.Id
            )
        );

        Test.stopTest();

        Case updatedCase = [
            SELECT Id,
                   Status,
                   Send_File_To_Metriport__c
            FROM Case
            WHERE Id = :c.Id
        ];

        System.assertEquals(
            'Closed',
            updatedCase.Status
        );

        System.assertEquals(
            true,
            updatedCase.Send_File_To_Metriport__c
        );
    }
}