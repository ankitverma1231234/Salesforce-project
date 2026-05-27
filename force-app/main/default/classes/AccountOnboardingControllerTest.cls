@isTest(SeeAllData=true)
public class AccountOnboardingControllerTest {

    @isTest
    static void testSendOnboardingLink_Success() {

        // =========================
        // FETCH EXISTING PERSON ACCOUNT
        // =========================
        Account acc = [
            SELECT Id, Name, IsPersonAccount, PersonEmail, 
                   PersonContactId, Phone, Onboarding_URL__c
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        // If URL is blank, update it
        if(String.isBlank(acc.Onboarding_URL__c)) {
            acc.Onboarding_URL__c = 'https://test.com/onboarding';
            update acc;
        }

        Test.startTest();

        AccountOnboardingNotificationController.sendOnboardingLink(acc.Id);

        Test.stopTest();

        // =========================
        // VERIFY SMS RECORD CREATED
        // =========================
        List<sra__Message_History__c> smsList = [
            SELECT Id, sra__Message_Body__c, sra__Related_Object_Id__c
            FROM sra__Message_History__c
            WHERE sra__Related_Object_Id__c = :acc.Id
        ];

        System.assert(smsList.size() > 0, 'SMS record should be created');
    }


    @isTest
    static void testSendOnboardingLink_NoURL() {

        Account acc = [
            SELECT Id, IsPersonAccount
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        acc.Onboarding_URL__c = null;
        update acc;

        Test.startTest();

        try {
            AccountOnboardingNotificationController.sendOnboardingLink(acc.Id);
            System.assert(true, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Onboarding URL is missing'));
        }

        Test.stopTest();
    }


   
}