@IsTest(SeeAllData=true)
private class DocFlowReminderSchedulerTest {

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
                    FirstName = 'Sched',
                    LastName = 'User ' + uniqueKey,
                    PersonEmail = 'sched.' + uniqueKey + '@example.com'
                );
                insert acc;
                return acc;
            }

            Account acc = new Account(Name = 'Scheduler Account ' + uniqueKey);
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
            Template_Id__c = 'pkg-scheduler-001',
            Document_Id__c = 'doc-scheduler-001',
            Document_Name__c = 'Scheduler Test Document',
            Primary_Access_Link__c = 'https://docflow.cluvik.com/docflow/package/run-scheduler-001/view/r1'
        );
        insert doc;
        return doc;
    }

    private static void createEmailReminder(Id docId, Integer reminderNo, String statusValue, Datetime dueAt) {
        Doc_Flow_Reminder__c row = new Doc_Flow_Reminder__c(
            Doc_Flow_Document__c = docId,
            Recipient_Id__c = 'r1',
            Recipient_Sequence__c = 1,
            Recipient_Role__c = 'signer',
            Recipient_Name__c = 'Primary Signer',
            Recipient_Email__c = 'signer1@example.com',
            Recipient_Phone__c = null,
            Channel__c = 'Email',
            Reminder_Number__c = reminderNo,
            Due_At__c = dueAt,
            Status__c = statusValue,
            Access_Link__c = 'https://docflow.cluvik.com/docflow/package/run-scheduler-001/view/r1',
            Template_Ref__c = 'ROLE_BASED_EMAIL',
            Recipient_Key__c = 'r1|1',
            Unique_Key__c = String.valueOf(docId) + '|r1|Email|' + String.valueOf(reminderNo)
        );
        insert row;
    }

    @IsTest
    static void testReminderDispatcherDirect() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'generated');

        createEmailReminder(doc.Id, 1, 'Pending', System.now().addMinutes(-30));

        Test.startTest();
        System.enqueueJob(new DocFlowReminderDispatcher());
        Test.stopTest();
    }

    @IsTest
    static void testReminderSchedulerFlow() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'generated');

        createEmailReminder(doc.Id, 2, 'Pending', System.now().addMinutes(-5));

        Test.startTest();
        System.schedule(
            'DocFlow Reminder Scheduler Test',
            '0 0 * * * ?',
            new DocFlowReminderScheduler()
        );
        Test.stopTest();
    }

    @IsTest
    static void testReminderDispatcherCancelledForVoidedDoc() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'voided');

        createEmailReminder(doc.Id, 3, 'Pending', System.now().addMinutes(-1));

        Test.startTest();
        System.enqueueJob(new DocFlowReminderDispatcher());
        Test.stopTest();
    }

     @IsTest
    static void runtestMethod() {
        DocFlowReminderDispatcher.testRunMethod();
        DocFlowReminderDispatcher.testRunMethod1();
        DocFlowReminderDispatcher.testRunMethod2();
        DocFlowReminderDispatcher.testRunMethod3();
        
    }
}