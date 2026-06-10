@IsTest
private class GoogleDrivePublicUrlServiceTest {
    private class DriveCalloutMock implements HttpCalloutMock {
        private Integer permissionStatus;
        private Integer fileStatus;
        private String fileResponseBody;
        private Integer callCount = 0;

        DriveCalloutMock(
            Integer permissionStatus,
            Integer fileStatus,
            String fileResponseBody
        ) {
            this.permissionStatus = permissionStatus;
            this.fileStatus = fileStatus;
            this.fileResponseBody = fileResponseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            callCount++;
            HttpResponse response = new HttpResponse();

            System.assertEquals('application/json', request.getHeader('Content-Type'));
            System.assert(
                request.getEndpoint().startsWith(
                    'callout:Test_Google_Drive/drive/v3/files/'
                )
            );
            System.assert(
                request.getEndpoint().contains('file+id%2Fwith%2Bcharacters')
            );

            if (callCount == 1) {
                System.assertEquals('POST', request.getMethod());
                System.assert(request.getEndpoint().endsWith('/permissions'));

                Map<String, Object> permissionBody =
                    (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                System.assertEquals('reader', permissionBody.get('role'));
                System.assertEquals('anyone', permissionBody.get('type'));

                response.setStatusCode(permissionStatus);
                response.setBody(
                    permissionStatus == 200 || permissionStatus == 201
                        ? '{"id":"anyoneWithLink"}'
                        : '{"error":"permission denied"}'
                );
                return response;
            }

            System.assertEquals(2, callCount);
            System.assertEquals('GET', request.getMethod());
            System.assert(
                request.getEndpoint().endsWith(
                    '?fields=webViewLink,webContentLink'
                )
            );
            response.setStatusCode(fileStatus);
            response.setBody(fileResponseBody);
            return response;
        }
    }

    @IsTest
    static void getPublicUrlReturnsWebViewLink() {
        Test.setMock(
            HttpCalloutMock.class,
            new DriveCalloutMock(
                201,
                200,
                '{"webViewLink":"https://drive.google.test/public-file",' +
                '"webContentLink":"https://drive.google.test/download"}'
            )
        );

        Test.startTest();
        String publicUrl = GoogleDrivePublicUrlService.getPublicUrl(
            'Test_Google_Drive',
            'file id/with+characters'
        );
        Test.stopTest();

        System.assertEquals(
            'https://drive.google.test/public-file',
            publicUrl
        );
    }

    @IsTest
    static void getPublicUrlAcceptsPermissionStatus200() {
        Test.setMock(
            HttpCalloutMock.class,
            new DriveCalloutMock(
                200,
                200,
                '{"webViewLink":"https://drive.google.test/status-200"}'
            )
        );

        System.assertEquals(
            'https://drive.google.test/status-200',
            GoogleDrivePublicUrlService.getPublicUrl(
                'Test_Google_Drive',
                'file id/with+characters'
            )
        );
    }

    @IsTest
    static void getPublicUrlRejectsPermissionFailure() {
        Test.setMock(
            HttpCalloutMock.class,
            new DriveCalloutMock(
                403,
                200,
                '{"webViewLink":"https://drive.google.test/not-returned"}'
            )
        );

        assertPublicUrlFailure('Test_Google_Drive', 'file id/with+characters');
    }

    @IsTest
    static void getPublicUrlRejectsFileDetailsFailure() {
        Test.setMock(
            HttpCalloutMock.class,
            new DriveCalloutMock(
                200,
                500,
                '{"error":"file details unavailable"}'
            )
        );

        assertPublicUrlFailure('Test_Google_Drive', 'file id/with+characters');
    }

    @IsTest
    static void getPublicUrlRejectsMissingWebViewLink() {
        Test.setMock(
            HttpCalloutMock.class,
            new DriveCalloutMock(
                200,
                200,
                '{"webContentLink":"https://drive.google.test/download-only"}'
            )
        );

        assertPublicUrlFailure('Test_Google_Drive', 'file id/with+characters');
    }

    @IsTest
    static void getPublicUrlRejectsBlankInputs() {
        assertPublicUrlFailure(null, 'file-id');
        assertPublicUrlFailure('   ', 'file-id');
        assertPublicUrlFailure('Test_Google_Drive', null);
        assertPublicUrlFailure('Test_Google_Drive', ' ');
    }

    @IsTest
    static void namedCredentialExistsHandlesTestInputs() {
        System.assertEquals(
            false,
            GoogleDrivePublicUrlService.namedCredentialExists(null)
        );
        System.assertEquals(
            false,
            GoogleDrivePublicUrlService.namedCredentialExists(' ')
        );
        System.assertEquals(
            true,
            GoogleDrivePublicUrlService.namedCredentialExists(
                'Test_Google_Drive'
            )
        );
    }

    private static void assertPublicUrlFailure(
        String namedCredential,
        String fileId
    ) {
        Boolean exceptionThrown = false;
        try {
            GoogleDrivePublicUrlService.getPublicUrl(
                namedCredential,
                fileId
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        System.assertEquals(
            true,
            exceptionThrown,
            'Expected the service to throw AuraHandledException.'
        );
    }
}