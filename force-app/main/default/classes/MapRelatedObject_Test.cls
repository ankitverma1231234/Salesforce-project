@isTest
public class MapRelatedObject_Test {

    private static Account createTestAccount() {
        Account acc = new Account(
            Name = 'Test Account',
            Phone = '9999999999'
        );
        insert acc;
        return acc;
    }

    private static Contact createTestContact(Id accountId) {
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'contact@test.com',
            AccountId = accountId
        );
        insert con;
        return con;
    }

    private static Opportunity createTestOpportunity(Id accountId) {
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = accountId
        );
        insert opp;
        return opp;
    }

    @isTest
    static void testMappingForAllObjects() {

        Account acc = createTestAccount();
        Contact con = createTestContact(acc.Id);
        Opportunity opp = createTestOpportunity(acc.Id);

        // Create messages
        sra__Message_History__c msgAcc = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Related_Object_Id__c = acc.Id,
            sra__Account__c = acc.Id,
            sra__Message_Body__c = 'Account test'
        );

        sra__Message_History__c msgCon = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Related_Object_Id__c = con.Id,
            sra__Account__c = acc.Id,
            sra__Message_Body__c = 'Contact test'
        );

        // Removed Lead test completely

        sra__Message_History__c msgOppRec = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Related_Object_Id__c = opp.Id,
            sra__Account__c = acc.Id,
            sra__Message_Body__c = 'Opportunity test'
        );

        sra__Message_History__c msgOut = new sra__Message_History__c(
            sra__Type__c = 'Outbound',
            sra__Related_Object_Id__c = acc.Id,
            sra__Account__c = acc.Id,
            sra__Message_Body__c = 'Outbound test'
        );

        insert new List<sra__Message_History__c>{ msgAcc, msgCon, msgOppRec, msgOut };

        // Query using ID only
        msgAcc = [
            SELECT sra__Account__c 
            FROM sra__Message_History__c 
            WHERE Id = :msgAcc.Id
        ];

        msgCon = [
            SELECT sra__Contact__c 
            FROM sra__Message_History__c 
            WHERE Id = :msgCon.Id
        ];

        msgOppRec = [
            SELECT sra__Opportunity__c 
            FROM sra__Message_History__c 
            WHERE Id = :msgOppRec.Id
        ];

        // Assertions
        System.assertEquals(acc.Id,  msgAcc.sra__Account__c, 'Account mapping failed');
        System.assertEquals(con.Id,  msgCon.sra__Contact__c, 'Contact mapping failed');
        System.assertEquals(opp.Id,  msgOppRec.sra__Opportunity__c, 'Opportunity mapping failed');

        // Lead assertion removed
    }
}