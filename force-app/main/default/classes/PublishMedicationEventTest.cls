@isTest
private class PublishMedicationEventTest {
    @testSetup
    public static void setupTestData() {
        Id sysAdminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id; 
        User usr = new User();
        usr.FirstName = 'Test';
        usr.LastName = 'User1';
        usr.Email = 'uniqueName1122' + '@test.org';
        usr.Username = 'uniqueName1122@test.org';
        usr.EmailEncodingKey = 'ISO-8859-1';
        usr.ProfileId = sysAdminProfileId;
        usr.Alias = 'un987';
        usr.TimeZoneSidKey = 'America/Los_Angeles';
        usr.LocaleSidKey = 'en_US';
        usr.LanguageLocaleKey = 'en_US';
        datetime yesterdayDate = datetime.newInstance(2025,05,1,11,00,0);
        usr.SecondLastLoginDateTime__c = yesterdayDate;
        insert usr;
    }
    
    @isTest
    static void testPublishMedicationEvent() {
        User usr = [SELECT Id, Contact.Account.Athena_Patient_Id__c, LastLoginDate, SecondLastLoginDateTime__c FROM User WHERE Username = 'uniqueName1122@test.org' LIMIT 1];
        PublishMedicationEvent.usr = usr;
        Test.startTest();
        PublishMedicationEvent.publishMedicationEvent();
        Test.stopTest();
    }
    
    @isTest
    static void testPublishMedicationEvent_Error() {
        Test.startTest();
        try {
            PublishMedicationEvent.publishMedicationEvent();
        } catch (Exception ex) {
            Assert.isNotNull(ex);
        }
        Test.stopTest();
    }
}