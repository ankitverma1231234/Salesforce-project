public class AccountOnboardingInvocable {
    
    @InvocableMethod(label='Send Onboarding Email and Update Account' 
                     description='Updates Account status to Pending, sets Description with onboarding URL, and sends email')
    public static void processOnboarding(List<FlowInput> requests) {
        List<Account> accountsToUpdate = new List<Account>();
        for (FlowInput request : requests) {
            if (request.accountId != null) {
                // Query the Account to get necessary details
                Account acc = [SELECT Id, IsPersonAccount,Onboarding_URL__c,Status__c, PersonEmail, PersonContactId 
                               FROM Account 
                               WHERE Id = :request.accountId 
                               LIMIT 1];
                
                // Construct the onboarding URL
                String onboardingUrl = 'https://portal.batoncare.com/member-onboarding?id=' + acc.PersonContactId;
                
                acc.Onboarding_URL__c = onboardingUrl;
                accountsToUpdate.add(acc);
            }
        }
        
        // Update Accounts
        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
    
    // Inner class to define input parameters for the Invocable method
    public class FlowInput {
        @InvocableVariable(label='Account Id' description='The Account record Id' required=true)
        public Id accountId;
    }
}