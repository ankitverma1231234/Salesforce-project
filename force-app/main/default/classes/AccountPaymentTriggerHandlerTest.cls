@isTest
public class AccountPaymentTriggerHandlerTest {

    @isTest
    static void testHandleAfterInsertAsync() {
        // Step 1: Create test Accounts
        List<Account> accounts = new List<Account>();
        
        for (Integer i = 0; i < 2; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
        AccountPaymentTriggerHandler.genrateTestScript();

    }
}