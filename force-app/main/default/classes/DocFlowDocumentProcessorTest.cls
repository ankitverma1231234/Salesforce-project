@IsTest(SeeAllData=true)
private class DocFlowDocumentProcessorTest {

    private static final String PACKAGE_ID = 'pkg-test-001';
    private static final String TEMPLATE_ID = 'tpl-template-001';

    private class SendRouterMockFull implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint().toLowerCase();
            String methodName = req.getMethod() == null ? '' : req.getMethod().toUpperCase();

            if (methodName == 'POST' && endpoint.contains('/api/public/packages/send')) {
                res.setStatusCode(200);
                res.setBody(
                    '{' +
                        '"success":true,' +
                        '"run_id":"run-proc-001",' +
                        '"package_id":"pkg-test-001",' +
                        '"status":"in_progress",' +
                        '"delivery_mode":"public_recipients",' +
                        '"public_link":"https://docflow.cluvik.com/docflow/package/run-proc-001/public/test-link",' +
                        '"recipient_links":[' +
                            '{' +
                                '"name":"Primary Signer",' +
                                '"email":"signer1@example.com",' +
                                '"role":"SIGN",' +
                                '"routing_order":1,' +
                                '"status":"notified",' +
                                '"access_link":"https://docflow.cluvik.com/docflow/package/run-proc-001/view/r1"' +
                            '},' +
                            '{' +
                                '"name":"Approver User",' +
                                '"email":"approver@example.com",' +
                                '"role":"APPROVE_REJECT",' +
                                '"routing_order":2,' +
                                '"status":"pending",' +
                                '"access_link":"https://docflow.cluvik.com/docflow/package/run-proc-001/view/r2"' +
                            '}' +
                        '],' +
                        '"documents":[' +
                            '{' +
                                '"document_id":"doc-proc-001",' +
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

            if (methodName == 'POST' && endpoint.contains('/api/v1/documents/generate-links')) {
                res.setStatusCode(200);
                res.setBody(
                    '{' +
                        '"success":true,' +
                        '"document_id":"doc-template-001",' +
                        '"document_name":"Template Test Document",' +
                        '"public_link":"https://docflow.cluvik.com/docflow/template/public/test-link",' +
                        '"recipient_links":[' +
                            '{' +
                                '"name":"Template Signer",' +
                                '"email":"template1@example.com",' +
                                '"role":"SIGN",' +
                                '"routing_order":1,' +
                                '"status":"notified",' +
                                '"access_link":"https://docflow.cluvik.com/docflow/template/view/r1"' +
                            '}' +
                        '],' +
                        '"message":"Template sent successfully"' +
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
                    LastName = 'Proc ' + uniqueKey,
                    PersonEmail = 'proc.' + uniqueKey + '@example.com'
                );
                insert acc;
                return acc;
            }

            Account acc = new Account(
                Name = 'DocFlow Processor ' + uniqueKey
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

    private static String buildPackageMetadataJson() {
        return JSON.serialize(new Map<String, Object>{
            'packageId' => PACKAGE_ID,
            'packageName' => 'Subscription Documents - Test',
            'templates' => new List<Object>{
                new Map<String, Object>{
                    'templateId' => 'tpl-sub-001',
                    'documentName' => '1. Subscription Agreement',
                    'templateName' => 'Subscription Agreement',
                    'sortOrder' => 1,
                    'templateVersion' => 1,
                    'isLatestVersion' => true,
                    'fields' => new List<Object>{
                        new Map<String, Object>{
                            'fieldId' => 'signature_1',
                            'fieldName' => 'Signature',
                            'fieldType' => 'signature',
                            'required' => true,
                            'isMerge' => false
                        },
                        new Map<String, Object>{
                            'fieldId' => 'merge_name_1',
                            'fieldName' => 'Member Name',
                            'fieldType' => 'merge',
                            'required' => false,
                            'isMerge' => true,
                            'mergeSource' => new Map<String, Object>{
                                'objectName' => 'Account',
                                'fieldName' => 'Name'
                            }
                        }
                    }
                }
            }
        });
    }

    private static String buildRecipientConfigJson(String emailOne, String emailTwo) {
        return JSON.serialize(new Map<String, Object>{
            'version' => '3.1',
            'sourceType' => 'package',
            'packageId' => PACKAGE_ID,
            'packageName' => 'Subscription Documents - Test',
            'fromAddress' => new Map<String, Object>{
                'value' => 'USER:' + UserInfo.getUserId(),
                'name' => UserInfo.getName(),
                'email' => UserInfo.getUserEmail(),
                'source' => 'USER'
            },
            'reminderSettings' => new Map<String, Object>{
                'enabled' => false,
                'intervalDays' => 1,
                'maxReminders' => 0
            },
            'recipients' => new List<Object>{
                new Map<String, Object>{
                    'recipientId' => 'r1',
                    'sequence' => 1,
                    'role' => 'signer',
                    'name' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => 'Primary Signer'
                    },
                    'email' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => emailOne
                    },
                    'phone' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => null
                    }
                },
                new Map<String, Object>{
                    'recipientId' => 'r2',
                    'sequence' => 2,
                    'role' => 'approver',
                    'name' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => 'Approver User'
                    },
                    'email' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => emailTwo
                    },
                    'phone' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => null
                    }
                }
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
    }

    private static String buildTemplateMetadataJson() {
        return JSON.serialize(new Map<String, Object>{
            'template_id' => TEMPLATE_ID,
            'template_name' => 'Template Test Document',
            'field_placements' => new List<Object>{
                new Map<String, Object>{
                    'field_id' => 'text_1',
                    'field_name' => 'Date Signed',
                    'field_type' => 'date',
                    'required' => true,
                    'is_merge' => false
                },
                new Map<String, Object>{
                    'field_id' => 'merge_1',
                    'field_name' => 'Member Name',
                    'field_type' => 'merge',
                    'required' => false,
                    'is_merge' => true,
                    'merge_source' => new Map<String, Object>{
                        'object' => 'Account',
                        'field_name' => 'Name'
                    }
                }
            }
        });
    }

    private static String buildTemplateRecipientConfigJson(String emailOne) {
        return JSON.serialize(new Map<String, Object>{
            'version' => '4.0',
            'sourceType' => 'template',
            'templateId' => TEMPLATE_ID,
            'templateName' => 'Template Test Document',
            'fromAddress' => new Map<String, Object>{
                'value' => 'USER:' + UserInfo.getUserId(),
                'name' => UserInfo.getName(),
                'email' => UserInfo.getUserEmail(),
                'source' => 'USER'
            },
            'reminderSettings' => new Map<String, Object>{
                'enabled' => false,
                'intervalDays' => 1,
                'maxReminders' => 0
            },
            'recipients' => new List<Object>{
                new Map<String, Object>{
                    'recipientId' => 'r1',
                    'sequence' => 1,
                    'role' => 'signer',
                    'name' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => 'Template Signer'
                    },
                    'email' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => emailOne
                    },
                    'phone' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'resolvedValue' => null
                    }
                }
            },
            'fieldAssignments' => new List<Object>{
                new Map<String, Object>{
                    'fieldId' => 'text_1',
                    'recipientId' => 'r1',
                    'isMerge' => false
                }
            },
            'mergeAssignments' => new List<Object>{
                new Map<String, Object>{
                    'fieldId' => 'merge_1',
                    'recipientId' => 'r1',
                    'isMerge' => true,
                    'mergeSource' => new Map<String, Object>{
                        'objectName' => 'Account',
                        'fieldName' => 'Name'
                    }
                }
            }
        });
    }

    @IsTest
    static void testProcessorSuccessInsertFlow() {
        Account acc = getUsableAccount();

        Test.setMock(HttpCalloutMock.class, new SendRouterMockFull());

        Test.startTest();

        insert new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'initiated',
            Template_Id__c = PACKAGE_ID,
            DocFlow_Source_Type__c = 'Package',
            Recipient_Config_Json__c = buildRecipientConfigJson('signer1@example.com', 'approver@example.com'),
            Package_Metadata_Json__c = buildPackageMetadataJson()
        );

        Test.stopTest();
    }

    @IsTest
    static void testProcessorInvalidJsonFlow() {
        Account acc = getUsableAccount();

        Test.startTest();

        insert new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'initiated',
            Template_Id__c = PACKAGE_ID,
            DocFlow_Source_Type__c = 'Package',
            Recipient_Config_Json__c = 'invalid-json',
            Package_Metadata_Json__c = buildPackageMetadataJson()
        );

        Test.stopTest();
    }

    @IsTest
    static void testProcessorUpdateToInitiatedFlow() {
        Account acc = getUsableAccount();

        Doc_Flow_Document__c doc = new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'draft',
            Template_Id__c = PACKAGE_ID,
            DocFlow_Source_Type__c = 'Package',
            Recipient_Config_Json__c = buildRecipientConfigJson('signer1@example.com', 'approver@example.com'),
            Package_Metadata_Json__c = buildPackageMetadataJson()
        );
        insert doc;

        Test.setMock(HttpCalloutMock.class, new SendRouterMockFull());

        Test.startTest();

        doc.Status__c = 'initiated';
        update doc;

        Test.stopTest();
    }

    @IsTest
    static void testProcessorTemplateSuccessInsertFlow() {
        Account acc = getUsableAccount();

        Test.setMock(HttpCalloutMock.class, new SendRouterMockFull());

        Test.startTest();

        insert new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'initiated',
            Template_Id__c = TEMPLATE_ID,
            DocFlow_Source_Type__c = 'Template',
            Recipient_Config_Json__c = buildTemplateRecipientConfigJson('template1@example.com'),
            Template_Metadata_Json__c = buildTemplateMetadataJson()
        );

        Test.stopTest();
    }

    @IsTest
    static void testProcessorTemplateInvalidJsonFlow() {
        Account acc = getUsableAccount();

        Test.startTest();

        insert new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'initiated',
            Template_Id__c = TEMPLATE_ID,
            DocFlow_Source_Type__c = 'Template',
            Recipient_Config_Json__c = 'invalid-json',
            Template_Metadata_Json__c = buildTemplateMetadataJson()
        );

        Test.stopTest();
    }

    @IsTest
    static void runtestMethod() {
        DocFlowDocumentProcessor.testRunMethod();
        DocFlowDocumentProcessor.testRunMethod1();
        DocFlowDocumentProcessor.testRunMethod2();
        DocFlowDocumentProcessor.testRunMethod3();
    }
}