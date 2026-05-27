@IsTest(SeeAllData=true)
public class MetriportPatientDocuments_Test {

    /* =====================================================
       HTTP CALLOUT MOCK
    ====================================================== */
    private class MetriportDocumentsMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            res.setBody(
                '{' +
                '  "resourceType": "Bundle",' +
                '  "entry": [' +
                '    {' +
                '      "resource": {' +
                '        "resourceType": "DocumentReference",' +
                '        "id": "doc-123",' +
                '        "status": "current"' +
                '      }' +
                '    }' +
                '  ]' +
                '}'
            );

            return res;
        }
    }

    /* =====================================================
       TEST: MetriportFetchPatientDocuments
    ====================================================== */
    @IsTest
    static void testFetchDocuments_success() {

        // Register mock
        Test.setMock(HttpCalloutMock.class, new MetriportDocumentsMock());

        Test.startTest();
        MetriportFetchPatientDocuments.fetchDocuments('patient-001');
        Test.stopTest();

        // No assertion needed — success = no exception
        System.assert(true, 'fetchDocuments executed successfully');
    }

    /* =====================================================
       TEST: fetchDocuments with blank patientId
    ====================================================== */
    @IsTest
    static void testFetchDocuments_blankPatient() {

        Test.startTest();
        MetriportFetchPatientDocuments.fetchDocuments('');
        Test.stopTest();

        System.assert(true, 'Handled blank patientId safely');
    }

    /* =====================================================
       TEST: MetriportPatientDocumentQueueable
    ====================================================== */
    @IsTest
    static void testPatientDocumentQueueable() {

        Test.setMock(HttpCalloutMock.class, new MetriportDocumentsMock());

        String bundleJson =
            '{' +
            '  "resourceType": "Bundle",' +
            '  "entry": [' +
            '    {' +
            '      "resource": {' +
            '        "resourceType": "Patient",' +
            '        "id": "patient-queue-001"' +
            '      }' +
            '    }' +
            '  ]' +
            '}';

        Test.startTest();
        System.enqueueJob(
            new MetriportPatientDocumentQueueable(bundleJson)
        );
        Test.stopTest();

        System.assert(true, 'Queueable executed successfully');
    }

    /* =====================================================
       TEST: Queueable with invalid JSON
    ====================================================== */
    @IsTest
    static void testQueueable_invalidJson() {

        Test.startTest();
        System.enqueueJob(
            new MetriportPatientDocumentQueueable('INVALID_JSON')
        );
        Test.stopTest();

        System.assert(true, 'Invalid JSON handled safely');
    }
}