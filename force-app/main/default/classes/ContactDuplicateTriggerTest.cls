@IsTest(seeAllData=true)
private class ContactDuplicateTriggerTest {

    @IsTest
    static void testInsertContact() {
        // Setup
        Account acc = [Select id From Account Where Metriport_Patient_Id__c = 'patient-123'];

        

        User someUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Contact c = [Select id From Contact Where Name = 'Brian Bernick' ];

        // Switch to Unassigned
        User unassignedUser = [SELECT Id FROM User WHERE LastName = 'Unassigned' LIMIT 1];
        c.OwnerId = unassignedUser.Id;
        update c;
        
        ContactTriggerHandler.genrateTestScript();
    }

}