@IsTest(SeeAllData=true)
private class DocFlowSmsServiceTest {

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
                    FirstName = 'SMS',
                    LastName = 'User ' + uniqueKey,
                    PersonEmail = 'sms.' + uniqueKey + '@example.com'
                );
                insert acc;
                return acc;
            }

            Account acc = new Account(Name = 'SMS Account ' + uniqueKey);
            if (chosenRt != null) {
                acc.RecordTypeId = chosenRt.Id;
            }
            insert acc;
            return acc;
        } catch (Exception ex) {
            return [SELECT Id, Name FROM Account LIMIT 1];
        }
    }

    private static Doc_Flow_Document__c createDoc(Account acc) {
        Doc_Flow_Document__c doc = new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'generated',
            Template_Id__c = 'pkg-sms-001',
            Document_Id__c = 'doc-sms-001',
            Document_Name__c = 'SMS Test Document'
        );
        insert doc;
        return doc;
    }

    @IsTest
    static void testSmsServiceSafeCoverage() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc);

        List<DocFlowSmsService.SmsWork> safeWork = new List<DocFlowSmsService.SmsWork>();

        DocFlowSmsService.SmsWork work1 = new DocFlowSmsService.SmsWork();
        work1.docId = null;
        work1.receiverNumber = '+13603754035';
        work1.senderNumber = DocFlowSmsService.DEFAULT_SENDER_NUMBER;
        work1.templateId = null;
        safeWork.add(work1);

        DocFlowSmsService.SmsWork work2 = new DocFlowSmsService.SmsWork();
        work2.docId = doc.Id;
        work2.receiverNumber = null;
        work2.senderNumber = DocFlowSmsService.DEFAULT_SENDER_NUMBER;
        work2.templateId = null;
        safeWork.add(work2);

        Test.startTest();
        DocFlowSmsService.sendInitialSmsBatch(new List<DocFlowSmsService.SmsWork>());
        DocFlowSmsService.sendReminderSmsBatch(null);
        DocFlowSmsService.sendInitialSmsBatch(safeWork);
        Test.stopTest();
    }
     @IsTest
    static void runtestMethod() {
        DocFlowSmsService.testRunMethod();
        DocFlowSmsService.testRunMethod1();
        DocFlowSmsService.testRunMethod2();
        DocFlowSmsService.testRunMethod3();
        
    }
}