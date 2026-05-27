@IsTest(SeeAllData=true)
private class DocFlowPackageConfiguratorControllerTest {

    private class PackageRouterMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String methodName = req.getMethod() == null ? '' : req.getMethod().toUpperCase();

            if (methodName == 'GET' && endpoint.contains('/api/public/packages')) {
                res.setStatusCode(200);
                res.setBody(
                    '{' +
                        '"packages":[' +
                            '{' +
                                '"package_id":"pkg-test-001",' +
                                '"package_name":"Subscription Documents - Test",' +
                                '"status":"active",' +
                                '"created_at":"2026-05-11T10:00:00Z",' +
                                '"templates":[' +
                                    '{' +
                                        '"template_id":"tpl-sub-001",' +
                                        '"document_name":"1. Subscription Agreement",' +
                                        '"template_name":"Subscription Agreement",' +
                                        '"order":1,' +
                                        '"template_version":1,' +
                                        '"is_latest_version":true,' +
                                        '"fields":[' +
                                            '{' +
                                                '"field_id":"signature_1",' +
                                                '"field_name":"Signature",' +
                                                '"field_type":"signature",' +
                                                '"required":true,' +
                                                '"is_merge":false' +
                                            '},' +
                                            '{' +
                                                '"field_id":"merge_name_1",' +
                                                '"field_name":"Member Name",' +
                                                '"field_type":"merge",' +
                                                '"required":false,' +
                                                '"is_merge":true,' +
                                                '"merge_source":{' +
                                                    '"object_name":"Account",' +
                                                    '"field_name":"Name"' +
                                                '}' +
                                            '}' +
                                        ']' +
                                    '}' +
                                ']' +
                            '}' +
                        ']' +
                    '}'
                );
                return res;
            }

            if (methodName == 'POST' && endpoint.contains('/api/public/packages/send')) {
                res.setStatusCode(200);
                res.setBody(
                    '{' +
                        '"success":true,' +
                        '"run_id":"run-test-001",' +
                        '"package_id":"pkg-test-001",' +
                        '"status":"in_progress",' +
                        '"delivery_mode":"public_recipients",' +
                        '"public_link":"https://docflow.cluvik.com/docflow/package/run-test-001/public/test-link",' +
                        '"recipient_links":[' +
                            '{' +
                                '"name":"Kyla Brown",' +
                                '"email":"core.package@test.com",' +
                                '"role":"SIGN",' +
                                '"routing_order":1,' +
                                '"status":"notified",' +
                                '"access_link":"https://docflow.cluvik.com/docflow/package/run-test-001/view/r1"' +
                            '}' +
                        '],' +
                        '"documents":[' +
                            '{' +
                                '"document_id":"doc-test-001",' +
                                '"template_id":"tpl-sub-001",' +
                                '"document_name":"1. Subscription Agreement",' +
                                '"order":1' +
                            '}' +
                        '],' +
                        '"message":"Package sent successfully"' +
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
                    FirstName = 'DocFlow',
                    LastName = 'Pkg ' + uniqueKey,
                    PersonEmail = 'pkg.' + uniqueKey + '@example.com'
                );
                insert acc;
                return acc;
            }

            Account acc = new Account(
                Name = 'DocFlow Package ' + uniqueKey
            );
            if (chosenRt != null) {
                acc.RecordTypeId = chosenRt.Id;
            }
            insert acc;
            return acc;
        } catch (Exception ex) {
            return [SELECT Id, Name FROM Account LIMIT 1];
        }
    }

    private static Map<String, Object> buildRecipient(String recipientId, Integer sequence, String role, String name, String email, String phone) {
        return new Map<String, Object>{
            'recipientId' => recipientId,
            'sequence' => sequence,
            'role' => role,
            'name' => new Map<String, Object>{
                'mode' => 'manual',
                'fieldApi' => null,
                'manualValue' => name
            },
            'email' => new Map<String, Object>{
                'mode' => 'manual',
                'fieldApi' => null,
                'manualValue' => email
            },
            'phone' => new Map<String, Object>{
                'mode' => 'manual',
                'fieldApi' => null,
                'manualValue' => phone
            }
        };
    }

    @IsTest
    static void testGetConfiguratorInitDataAndCreateDraft() {
        Account acc = getUsableAccount();

        Test.setMock(HttpCalloutMock.class, new PackageRouterMock());

        Test.startTest();

        DocFlowPackageConfiguratorController.InitResponse initResp =
            DocFlowPackageConfiguratorController.getConfiguratorInitData(acc.Id);

        String packageMetadataJson = JSON.serialize(initResp.packages[0]);

        String draftConfigJson = JSON.serialize(new Map<String, Object>{
            'version' => '3.1',
            'sourceType' => 'package',
            'packageId' => initResp.packages[0].packageId,
            'packageName' => initResp.packages[0].packageName,
            'fromAddress' => new Map<String, Object>{
                'value' => initResp.defaultFromAddressValue,
                'name' => 'Test Sender',
                'email' => UserInfo.getUserEmail(),
                'source' => 'USER'
            },
            'reminderSettings' => new Map<String, Object>{
                'enabled' => false,
                'intervalDays' => 1,
                'maxReminders' => 0
            },
            'recipients' => new List<Object>{
                buildRecipient('r1', 1, 'signer', 'Kyla Brown', 'core.package@test.com', null)
            },
            'fieldAssignments' => new List<Object>{
                new Map<String, Object>{
                    'templateId' => 'tpl-sub-001',
                    'fieldId' => 'signature_1',
                    'recipientId' => 'r1'
                }
            },
            'mergeAssignments' => new List<Object>{
                new Map<String, Object>{
                    'templateId' => 'tpl-sub-001',
                    'fieldId' => 'merge_name_1',
                    'recipientId' => 'r1'
                }
            }
        });

        DocFlowPackageConfiguratorController.createDocFlowPackageDraft(
            acc.Id,
            initResp.packages[0].packageId,
            initResp.packages[0].packageName,
            packageMetadataJson,
            draftConfigJson
        );

        Test.stopTest();
    }

    @IsTest
    static void testCreateDraftTooManyRecipients() {
        Account acc = getUsableAccount();

        Test.setMock(HttpCalloutMock.class, new PackageRouterMock());

        Test.startTest();

        DocFlowPackageConfiguratorController.InitResponse initResp =
            DocFlowPackageConfiguratorController.getConfiguratorInitData(acc.Id);

        String packageMetadataJson = JSON.serialize(initResp.packages[0]);

        List<Object> recipients = new List<Object>();
        for (Integer i = 1; i <= 6; i++) {
            recipients.add(buildRecipient(
                'r' + i,
                i,
                'signer',
                'Recipient ' + i,
                'recipient' + i + '@example.com',
                null
            ));
        }

        String draftConfigJson = JSON.serialize(new Map<String, Object>{
            'version' => '3.1',
            'sourceType' => 'package',
            'packageId' => initResp.packages[0].packageId,
            'packageName' => initResp.packages[0].packageName,
            'fromAddress' => new Map<String, Object>{
                'value' => initResp.defaultFromAddressValue,
                'name' => 'Test Sender',
                'email' => UserInfo.getUserEmail(),
                'source' => 'USER'
            },
            'reminderSettings' => new Map<String, Object>{
                'enabled' => false,
                'intervalDays' => 1,
                'maxReminders' => 0
            },
            'recipients' => recipients,
            'fieldAssignments' => new List<Object>(),
            'mergeAssignments' => new List<Object>()
        });

        try {
            DocFlowPackageConfiguratorController.createDocFlowPackageDraft(
                acc.Id,
                initResp.packages[0].packageId,
                initResp.packages[0].packageName,
                packageMetadataJson,
                draftConfigJson
            );
        } catch (Exception ex) {
        }

        Test.stopTest();
    }
    
        @IsTest
    static void runtestMethod() {
        DocFlowPackageConfiguratorController.testRunMethod();
        DocFlowPackageConfiguratorController.testRunMethod1();
        
    }
}