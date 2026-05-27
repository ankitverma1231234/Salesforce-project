@IsTest(SeeAllData=true)
private class DocFlowTempConfiguratorControllerTest {

    private class TemplateListMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"success": true,' +
                    '"data": [' +
                        '{' +
                            '"template_id": "tpl-001",' +
                            '"template_name": "Consent Template",' +
                            '"status": "active",' +
                            '"version": 1,' +
                            '"is_latest_version": true,' +
                            '"field_placements": [' +
                                '{' +
                                    '"id": "text_1",' +
                                    '"name": "Date Signed",' +
                                    '"type": "date",' +
                                    '"required": true' +
                                '},' +
                                '{' +
                                    '"id": "merge_1",' +
                                    '"name": "Merge Field 1",' +
                                    '"type": "merge",' +
                                    '"required": false,' +
                                    '"merge_source": {' +
                                        '"object": "Account",' +
                                        '"field_name": "Name"' +
                                    '}' +
                                '}' +
                            ']' +
                        '}' +
                    ']' +
                '}'
            );
            return res;
        }
    }

    private static Id getAnyAccountId() {
        List<Account> existingAccounts = [SELECT Id FROM Account LIMIT 1];
        if (!existingAccounts.isEmpty()) {
            return existingAccounts[0].Id;
        }

        return createFallbackAccount();
    }

    private static Id createFallbackAccount() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Account.fields.getMap();

        Account acc = new Account();

        if (fieldMap.containsKey('Name')) {
            acc.put('Name', 'DocFlow Template Test');
        }

        if (fieldMap.containsKey('FirstName')) {
            acc.put('FirstName', 'DocFlow');
        }

        if (fieldMap.containsKey('LastName')) {
            acc.put('LastName', 'Template');
        }

        Id recordTypeId = getAvailableAccountRecordTypeId();
        if (recordTypeId != null) {
            acc.put('RecordTypeId', recordTypeId);
        }

        insert acc;
        return acc.Id;
    }

    private static Id getAvailableAccountRecordTypeId() {
    for (Schema.RecordTypeInfo rti : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
        if (rti.isAvailable()) {
            return rti.getRecordTypeId();
        }
    }
    return null;
}

    private static String buildTemplateMetadataJson(String templateId, String templateName) {
    Map<String, Object> templateMetadata = new Map<String, Object>{
        'template_id' => templateId,
        'template_name' => templateName,
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
                'field_name' => 'Merge Field 1',
                'field_type' => 'merge',
                'required' => false,
                'is_merge' => true,
                'merge_source' => new Map<String, Object>{
                    'object' => 'Account',
                    'field_name' => 'Name'
                }
            }
        }
    };

    return JSON.serialize(templateMetadata);
}

    @IsTest
    static void testGetTemplateConfiguratorInitData() {
        Id accountId = getAnyAccountId();

        Test.setMock(HttpCalloutMock.class, new TemplateListMock());

        Test.startTest();
        DocFlowTemplateConfiguratorController.InitResponse response =
            DocFlowTemplateConfiguratorController.getTemplateConfiguratorInitData(accountId);
        Test.stopTest();

        System.debug(response);
    }

    @IsTest
    static void testCreateDocFlowTemplateDraftManualRecipient() {
        Id accountId = getAnyAccountId();

        String templateId = 'tpl-001';
        String templateName = 'Consent Template';
        String templateMetadataJson = buildTemplateMetadataJson(templateId, templateName);

        Map<String, Object> draftConfig = new Map<String, Object>{
            'templateId' => templateId,
            'templateName' => templateName,
            'documentName' => 'Consent Template Draft',
            'fromAddress' => new Map<String, Object>{
                'value' => 'USER:' + UserInfo.getUserId()
            },
            'reminderSettings' => new Map<String, Object>{
                'enabled' => true,
                'intervalDays' => 1,
                'maxReminders' => 2
            },
            'recipients' => new List<Object>{
                new Map<String, Object>{
                    'recipientId' => 'r1',
                    'sequence' => 1,
                    'role' => 'signer',
                    'name' => new Map<String, Object>{
                        'mode' => 'manual',
                        'manualValue' => 'Kyla Brown'
                    },
                    'email' => new Map<String, Object>{
                        'mode' => 'manual',
                        'manualValue' => 'operations@amroar.com'
                    },
                    'phone' => new Map<String, Object>{
                        'mode' => 'manual',
                        'manualValue' => '+13603754035'
                    }
                }
            },
            'fieldAssignments' => new List<Object>{
                new Map<String, Object>{
                    'fieldId' => 'text_1',
                    'recipientId' => 'r1'
                }
            },
            'mergeAssignments' => new List<Object>{
                new Map<String, Object>{
                    'fieldId' => 'merge_1',
                    'recipientId' => 'r1'
                }
            }
        };

        Test.startTest();
        Id docId = DocFlowTemplateConfiguratorController.createDocFlowTemplateDraft(
            accountId,
            templateId,
            templateName,
            templateMetadataJson,
            JSON.serialize(draftConfig)
        );
        Test.stopTest();

        System.debug(docId);
    }

    @IsTest
    static void testCreateDocFlowTemplateDraftFieldBasedName() {
        Id accountId = getAnyAccountId();

        String templateId = 'tpl-002';
        String templateName = 'Consent Template Field Mode';
        String templateMetadataJson = buildTemplateMetadataJson(templateId, templateName);

        Map<String, Object> draftConfig = new Map<String, Object>{
            'templateId' => templateId,
            'templateName' => templateName,
            'documentName' => 'Consent Template Field Draft',
            'fromAddress' => new Map<String, Object>{
                'value' => 'USER:' + UserInfo.getUserId()
            },
            'reminderSettings' => new Map<String, Object>{
                'enabled' => true,
                'intervalDays' => 2,
                'maxReminders' => 3
            },
            'recipients' => new List<Object>{
                new Map<String, Object>{
                    'recipientId' => 'r1',
                    'sequence' => 1,
                    'role' => 'signer',
                    'name' => new Map<String, Object>{
                        'mode' => 'field',
                        'fieldApi' => 'Name'
                    },
                    'email' => new Map<String, Object>{
                        'mode' => 'manual',
                        'manualValue' => 'operations@amroar.com'
                    },
                    'phone' => new Map<String, Object>{
                        'mode' => 'manual',
                        'manualValue' => '+13603754035'
                    }
                }
            },
            'fieldAssignments' => new List<Object>{
                new Map<String, Object>{
                    'fieldId' => 'text_1',
                    'recipientId' => 'r1'
                }
            },
            'mergeAssignments' => new List<Object>{
                new Map<String, Object>{
                    'fieldId' => 'merge_1',
                    'recipientId' => 'r1'
                }
            }
        };

        Test.startTest();
        Id docId = DocFlowTemplateConfiguratorController.createDocFlowTemplateDraft(
            accountId,
            templateId,
            templateName,
            templateMetadataJson,
            JSON.serialize(draftConfig)
        );
        Test.stopTest();

        System.debug(docId);
    }
}