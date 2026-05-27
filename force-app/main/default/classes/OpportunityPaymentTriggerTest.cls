@isTest
public class OpportunityPaymentTriggerTest {

    @isTest
    static void testPaymentIntentTriggerHandler() {
        Account testAccount = new Account(
            Name = 'Test Account',
            Industry = 'Technology',
            Type = 'Prospect'
        );
        insert testAccount;
        
        // Create a test Opportunity
        Opportunity testOpportunity = new Opportunity(
            Name = 'Test Tesla Deal',
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            AccountId = testAccount.Id,
            Amount = 50000
        );
        insert testOpportunity;
        
        OpportunityPaymentTriggerHandler.genrateTestScript();

        
    }
}