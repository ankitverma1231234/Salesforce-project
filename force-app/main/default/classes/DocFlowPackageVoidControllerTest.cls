@IsTest(SeeAllData=true)
private class DocFlowPackageVoidControllerTest {

    private class DocumentVoidMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String methodName = req.getMethod() == null ? '' : req.getMethod().toUpperCase();

            if (methodName == 'POST' && endpoint.contains('/api/docflow/public/documents/') && endpoint.endsWith('/void')) {
                res.setStatusCode(200);
                res.setBody(
                    '{' +
                        '"success":true,' +
                        '"already_voided":false,' +
                        '"document_id":"doc-void-001",' +
                        '"voided_at":"2026-05-11T12:00:00Z",' +
                        '"void_reason":"Test void from Apex"' +
                    '}'
                );
                return res;
            }

            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    private static Account getUsableAccount() {
        List<Account> personAccounts = [
            SELECT Id, Name, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];
        if (!personAccounts.isEmpty()) {
            return personAccounts[0];
        }

        List<Account> anyAccounts = [
            SELECT Id, Name
            FROM Account
            LIMIT 1
        ];
        if (!anyAccounts.isEmpty()) {
            return anyAccounts[0];
        }

        RecordType chosenRt = null;
        List<RecordType> rts = [
            SELECT Id, DeveloperName, Name, IsPersonType
            FROM RecordType
            WHERE SObjectType = 'Account'
              AND IsActive = true
            ORDER BY IsPersonType DESC, DeveloperName
        ];
        if (!rts.isEmpty()) {
            chosenRt = rts[0];
        }

        String uniqueKey = String.valueOf(Datetime.now().getTime());

        try {
            if (chosenRt != null && chosenRt.IsPersonType) {
                Account acc = new Account(
                    RecordTypeId = chosenRt.Id,
                    FirstName = 'Void',
                    LastName = 'User ' + uniqueKey,
                    PersonEmail = 'void.' + uniqueKey + '@example.com'
                );
                insert acc;
                return acc;
            }

            Account acc = new Account(Name = 'Void Account ' + uniqueKey);
            if (chosenRt != null) {
                acc.RecordTypeId = chosenRt.Id;
            }
            insert acc;
            return acc;
        } catch (Exception ex) {
            return [SELECT Id, Name FROM Account LIMIT 1];
        }
    }

    private static Doc_Flow_Document__c createVoidDoc(Account acc, String documentId, String statusValue) {
        Doc_Flow_Document__c doc = new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = statusValue,
            Template_Id__c = 'pkg-void-001',
            Document_Id__c = documentId,
            Document_Name__c = 'Subscription Agreement - Void Test',
            Primary_Access_Link__c = 'https://docflow.cluvik.com/docflow/package/run-void-001/view/r1',
            Package_Metadata_Json__c = JSON.serialize(new Map<String, Object>{
                'packageId' => 'pkg-void-001',
                'packageName' => 'Subscription Documents - Void Test'
            }),
            Response_Json__c = JSON.serialize(new Map<String, Object>{
                'success' => true,
                'run_id' => 'run-void-001',
                'package_id' => 'pkg-void-001',
                'package_name' => 'Subscription Documents - Void Test',
                'status' => 'in_progress',
                'recipient_links' => new List<Object>{
                    new Map<String, Object>{
                        'name' => 'Primary Signer',
                        'email' => 'void.signer@example.com',
                        'role' => 'SIGN',
                        'routing_order' => 1,
                        'status' => 'notified',
                        'access_link' => 'https://docflow.cluvik.com/docflow/package/run-void-001/view/r1'
                    }
                },
                'documents' => new List<Object>{
                    new Map<String, Object>{
                        'document_id' => documentId,
                        'template_id' => 'tpl-void-001',
                        'document_name' => 'Subscription Agreement - Void Test',
                        'order' => 1
                    }
                }
            })
        );
        insert doc;
        return doc;
    }

    @IsTest
    static void testGetVoidInitData() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createVoidDoc(acc, 'doc-void-init-001', 'generated');

        Test.startTest();
        DocFlowPackageVoidController.InitResponse response =
            DocFlowPackageVoidController.getVoidInitData(doc.Id);
        System.debug(response);
        Test.stopTest();
    }

    @IsTest
    static void testVoidDocumentSuccess() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createVoidDoc(acc, 'doc-void-001', 'generated');

        Test.setMock(HttpCalloutMock.class, new DocumentVoidMock());

        Test.startTest();
        DocFlowPackageVoidController.VoidActionResponse response =
            DocFlowPackageVoidController.voidPackage(doc.Id, 'Test void from Apex');
        System.debug(response);
        Test.stopTest();
    }

    @IsTest
    static void testVoidDocumentAlreadyVoided() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createVoidDoc(acc, 'doc-void-already-001', 'voided');

        Test.startTest();
        DocFlowPackageVoidController.VoidActionResponse response =
            DocFlowPackageVoidController.voidPackage(doc.Id, 'Already voided test');
        System.debug(response);
        Test.stopTest();
    }

    @IsTest
    static void testVoidDocumentWithMissingResponseDocumentIdFallback() {
        Account acc = getUsableAccount();

        Doc_Flow_Document__c doc = new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'generated',
            Template_Id__c = 'pkg-void-002',
            Document_Id__c = 'doc-void-002',
            Document_Name__c = 'Void Fallback Test',
            Primary_Access_Link__c = 'https://docflow.cluvik.com/docflow/package/run-void-002/view/r1',
            Package_Metadata_Json__c = JSON.serialize(new Map<String, Object>{
                'packageId' => 'pkg-void-002',
                'packageName' => 'Subscription Documents - Void Test 2'
            }),
            Response_Json__c = JSON.serialize(new Map<String, Object>{
                'success' => true,
                'run_id' => 'run-void-002',
                'package_id' => 'pkg-void-002',
                'package_name' => 'Subscription Documents - Void Test 2',
                'status' => 'in_progress'
            })
        );
        insert doc;

        Test.setMock(HttpCalloutMock.class, new DocumentVoidMock());

        Test.startTest();
        DocFlowPackageVoidController.VoidActionResponse response =
            DocFlowPackageVoidController.voidPackage(doc.Id, 'Fallback document id test');
        System.debug(response);
        Test.stopTest();
    }
}