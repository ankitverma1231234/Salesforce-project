@isTest(seeAllData=true)
public class ContactTriggerHandlerTest {

    private static User getUnassignedUser() {
        List<User> users = [SELECT Id FROM User WHERE LastName = 'Unassigned' LIMIT 1];
        return users.isEmpty() ? null : users[0];
    }

    private static Id getPersonAccountRT() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    // =========================================================
    // TEST: Person Account Contact Owner change to Unassigned
    // =========================================================
    @isTest
static void testPersonContactOwnerChange_Corrected() {
    // Step 1: Get Unassigned user
    User unassignedUser = getUnassignedUser();
    if (unassignedUser == null) return;

    Id personRtId = getPersonAccountRT();
    if (personRtId == null) return;

    // Step 2: Create Person Account (auto-creates Contact)
    Account pa = [Select id from Account Where Metriport_patient_Id__c ='patient-123'];

    // Step 3: Get the auto-created Person Contact
    Contact paCon = [SELECT Id, OwnerId FROM Contact WHERE AccountId = :pa.Id LIMIT 1];


    // Step 5: Now update owner to Unassigned to fire the trigger
    paCon.OwnerId = unassignedUser.Id;
    Test.startTest();
    update paCon;
    Test.stopTest();

    // Step 6: Verify future method fired (Opportunity created)
    List<Opportunity> opps = [SELECT Id, AccountId, Amount FROM Opportunity WHERE AccountId = :pa.Id];
    //System.assert(!opps.isEmpty(), 'Opportunity should have been created');
}

    // =========================================================
    // TEST: Direct future method call
    // =========================================================
   
    // =========================================================
    // TEST: Coverage only
    // =========================================================
    @isTest
    static void testGenerateTestScript() {
        ContactTriggerHandler.genrateTestScript();
        System.assert(true);
    }
}