@IsTest(SeeAllData=true)
private class DocFlowReminderServiceTest {

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
                    FirstName = 'Reminder',
                    LastName = 'User ' + uniqueKey,
                    PersonEmail = 'reminder.' + uniqueKey + '@example.com'
                );
                insert acc;
                return acc;
            }

            Account acc = new Account(Name = 'Reminder Account ' + uniqueKey);
            if (chosenRt != null) {
                acc.RecordTypeId = chosenRt.Id;
            }
            insert acc;
            return acc;
        } catch (Exception ex) {
            return [SELECT Id, Name FROM Account LIMIT 1];
        }
    }

    private static Doc_Flow_Document__c createDoc(Account acc, String statusValue) {
        Doc_Flow_Document__c doc = new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = statusValue,
            Template_Id__c = 'pkg-reminder-001',
            Document_Id__c = 'doc-reminder-001',
            Document_Name__c = 'Reminder Test Document',
            Primary_Access_Link__c = 'https://docflow.cluvik.com/docflow/package/run-reminder-001/view/r1',
            Recipient_Config_Json__c = JSON.serialize(new Map<String, Object>{
                'version' => '3.1',
                'sourceType' => 'package',
                'packageId' => 'pkg-reminder-001',
                'packageName' => 'Reminder Package Test',
                'fromAddress' => new Map<String, Object>{
                    'value' => 'USER:' + UserInfo.getUserId(),
                    'name' => UserInfo.getName(),
                    'email' => UserInfo.getUserEmail(),
                    'source' => 'USER'
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
                        'name' => new Map<String, Object>{ 'resolvedValue' => 'Primary Signer' },
                        'email' => new Map<String, Object>{ 'resolvedValue' => 'signer1@example.com' },
                        'phone' => new Map<String, Object>{ 'resolvedValue' => null }
                    },
                    new Map<String, Object>{
                        'recipientId' => 'r2',
                        'sequence' => 2,
                        'role' => 'approver',
                        'name' => new Map<String, Object>{ 'resolvedValue' => 'Approver User' },
                        'email' => new Map<String, Object>{ 'resolvedValue' => 'approver@example.com' },
                        'phone' => new Map<String, Object>{ 'resolvedValue' => null }
                    }
                },
                'fieldAssignments' => new List<Object>(),
                'mergeAssignments' => new List<Object>()
            })
        );
        insert doc;
        return doc;
    }

    @IsTest
    static void testActivateInitialRecipientReminders() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'generated');

        Test.startTest();
        DocFlowReminderService.activateInitialRecipientReminders(
            new List<Doc_Flow_Document__c>{ doc }
        );
        Test.stopTest();
    }

    @IsTest
    static void testActivateRecipientRemindersAndCancel() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'generated');

        Test.startTest();

        DocFlowReminderService.activateRecipientReminders(
            doc.Id,
            'r2',
            2,
            'approver',
            'Approver User',
            'approver@example.com',
            null,
            'https://docflow.cluvik.com/docflow/package/run-reminder-001/view/r2'
        );

        DocFlowReminderService.cancelPendingRemindersForDocument(doc.Id);

        Test.stopTest();
    }

    @IsTest
    static void testActivateRecipientRemindersVoidedDoc() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'voided');

        Test.startTest();

        DocFlowReminderService.activateRecipientReminders(
            doc.Id,
            'r1',
            1,
            'signer',
            'Primary Signer',
            'signer1@example.com',
            null,
            'https://docflow.cluvik.com/docflow/package/run-reminder-001/view/r1'
        );

        Test.stopTest();
    }
}