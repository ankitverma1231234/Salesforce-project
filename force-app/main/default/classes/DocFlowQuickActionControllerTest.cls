@IsTest(SeeAllData=true)
private class DocFlowQuickActionControllerTest {

    private static Account getExistingAccount() {
        List<Account> personAccounts = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE PersonContactId != null
            LIMIT 1
        ];

        if (!personAccounts.isEmpty()) {
            return personAccounts[0];
        }

        List<Account> anyAccounts = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        return anyAccounts.isEmpty() ? null : anyAccounts[0];
    }

    @IsTest
    static void testGetRecipientInitDataAndCreateDocFlowDocumentWithConfig() {
        Account acc = getExistingAccount();
        if (acc == null) {
            return;
        }

        DocFlowQuickActionController.InitResponse initResp;

        Test.startTest();

        initResp = DocFlowQuickActionController.getRecipientInitData(acc.Id);

        String configJson = JSON.serialize(new Map<String, Object>{
            'version' => '2.0',
            'fromAddress' => new Map<String, Object>{
                'value' => initResp.defaultFromAddressValue,
                'name' => 'Test User',
                'email' => UserInfo.getUserEmail(),
                'source' => 'USER'
            },
            'recipients' => new List<Object>{
                new Map<String, Object>{
                    'sequence' => 1,
                    'routingOrder' => 1,
                    'type' => 'Member',
                    'role' => 'signer',
                    'name' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'manualValue' => 'Kyla Brown'
                    },
                    'email' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'manualValue' => 'shivam@amroar.com'
                    },
                    'phone' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'manualValue' => '9196487787878'
                    }
                }
            }
        });

        DocFlowQuickActionController.createDocFlowDocumentWithConfig(
            acc.Id,
            'dummy-template-id',
            configJson
        );

        Test.stopTest();
    }

    @IsTest
    static void testCreateDocFlowDocumentWithMixedModes() {
        Account acc = getExistingAccount();
        if (acc == null) {
            return;
        }

        DocFlowQuickActionController.InitResponse initResp =
            DocFlowQuickActionController.getRecipientInitData(acc.Id);

        Test.startTest();

        String configJson = JSON.serialize(new Map<String, Object>{
            'version' => '2.0',
            'fromAddress' => new Map<String, Object>{
                'value' => initResp.defaultFromAddressValue,
                'name' => 'Test User',
                'email' => UserInfo.getUserEmail(),
                'source' => 'USER'
            },
            'recipients' => new List<Object>{
                new Map<String, Object>{
                    'sequence' => 1,
                    'routingOrder' => 1,
                    'type' => 'Member',
                    'role' => 'signer',
                    'name' => new Map<String, Object>{
                        'mode' => 'field',
                        'fieldApi' => 'Name',
                        'manualValue' => null
                    },
                    'email' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'manualValue' => 'shivam@amroar.com'
                    },
                    'phone' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'manualValue' => '+9196487787878'
                    }
                },
                new Map<String, Object>{
                    'sequence' => 2,
                    'routingOrder' => 2,
                    'type' => 'Surrogate',
                    'role' => 'reviewer',
                    'name' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'manualValue' => 'Surrogate User'
                    },
                    'email' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'manualValue' => 'reviewer@amroar.com'
                    },
                    'phone' => new Map<String, Object>{
                        'mode' => 'manual',
                        'fieldApi' => null,
                        'manualValue' => null
                    }
                }
            }
        });

        DocFlowQuickActionController.createDocFlowDocumentWithConfig(
            acc.Id,
            'dummy-template-id-2',
            configJson
        );

        Test.stopTest();
    }

    @IsTest
    static void testCreateDocFlowDocumentTooManyRecipients() {
        Account acc = getExistingAccount();
        if (acc == null) {
            return;
        }

        DocFlowQuickActionController.InitResponse initResp =
            DocFlowQuickActionController.getRecipientInitData(acc.Id);

        List<Object> recipients = new List<Object>();

        for (Integer i = 1; i <= 6; i++) {
            recipients.add(new Map<String, Object>{
                'sequence' => i,
                'routingOrder' => i,
                'type' => 'Member',
                'role' => 'signer',
                'name' => new Map<String, Object>{
                    'mode' => 'manual',
                    'fieldApi' => null,
                    'manualValue' => 'Name ' + i
                },
                'email' => new Map<String, Object>{
                    'mode' => 'manual',
                    'fieldApi' => null,
                    'manualValue' => 'user' + i + '@amroar.com'
                },
                'phone' => new Map<String, Object>{
                    'mode' => 'manual',
                    'fieldApi' => null,
                    'manualValue' => null
                }
            });
        }

        String configJson = JSON.serialize(new Map<String, Object>{
            'version' => '2.0',
            'fromAddress' => new Map<String, Object>{
                'value' => initResp.defaultFromAddressValue,
                'name' => 'Test User',
                'email' => UserInfo.getUserEmail(),
                'source' => 'USER'
            },
            'recipients' => recipients
        });

        Test.startTest();
        try {
            DocFlowQuickActionController.createDocFlowDocumentWithConfig(
                acc.Id,
                'dummy-template-id-3',
                configJson
            );
        } catch (Exception ex) {
        }
        Test.stopTest();
    }
    @IsTest
    static void testMethodRun() {
        DocFlowDocumentProcessor.testRunMethod();
        DocFlowDocumentProcessor.testRunMethod1();
    }
}