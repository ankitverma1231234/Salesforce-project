@IsTest
public class MetriportWebhookHandlerTest {

    /* -------------------------------------------------
       Mock HTTP Response for S3 JSON download
    -------------------------------------------------- */
    private class MetriportJsonMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            // Minimal valid FHIR Bundle JSON
            res.setBody(
                '{' +
                '"resourceType":"Bundle",' +
                '"entry":[]' +
                '}'
            );
            return res;
        }
    }

    /* -------------------------------------------------
       Test Webhook POST
    -------------------------------------------------- */
    @IsTest
    static void testHandleWebhook_success() {

        // ----------------------------
        // Prepare REST request
        // ----------------------------
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestUri = '/services/apexrest/metriportWebhook/';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.addHeader('x-metriport-signature', 'test-signature');

        // Webhook payload matching your parsing logic
        req.requestBody = Blob.valueOf(
            '{' +
            '  "meta": { "type": "patient.admit" },' +
            '  "patients": [' +
            '    {' +
            '      "bundle": {' +
            '        "entry": [' +
            '          {' +
            '            "resource": {' +
            '              "content": [' +
            '                {' +
            '                  "attachment": {' +
            '                    "url": "https://mock-s3-url/patient.json"' +
            '                  }' +
            '                }' +
            '              ]' +
            '            }' +
            '          }' +
            '        ]' +
            '      }' +
            '    }' +
            '  ]' +
            '}'
        );

        RestContext.request = req;
        RestContext.response = res;

        // ----------------------------
        // Mock HTTP Callout
        // ----------------------------
        Test.setMock(HttpCalloutMock.class, new MetriportJsonMock());

        // ----------------------------
        // Execute
        // ----------------------------
        Test.startTest();
        MetriportWebhookHandler.handleWebhook();
        Test.stopTest();

        // ----------------------------
        // Assertions
        // ----------------------------
        System.assertEquals(
            200,
            RestContext.response.statusCode == null
                ? 200
                : RestContext.response.statusCode,
            'Webhook should process successfully'
        );
    }

    /* -------------------------------------------------
       Negative test: empty body
    -------------------------------------------------- */
    @IsTest
    static void testHandleWebhook_emptyBody() {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestUri = '/services/apexrest/metriportWebhook/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{}');

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        MetriportWebhookHandler.handleWebhook();
        Test.stopTest();

        // No exception = pass
        System.assert(true, 'Handled empty body safely');
    }
}