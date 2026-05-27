@isTest

public class CaseControllerTest {
 
    @isTest

    static void testGetCases() {

        // Create test Account

        Account acc = new Account(Name = 'Test Account');

        insert acc;
 
        // Create test Cases linked to Account

        List<Case> casesToInsert = new List<Case>();

        for (Integer i = 0; i < 5; i++) {

            casesToInsert.add(new Case(

                AccountId = acc.Id,

                Subject   = 'Test Case ' + i,

                Status    = 'New',

                Priority  = 'Medium',

                Origin    = 'Email'

            ));

        }

        insert casesToInsert;
 
        // Call the method

        Test.startTest();

        List<Case> results = CaseController.getCases(acc.Id);

        Test.stopTest();
 
       
    }
 
    @isTest

    static void testGetCases_NoCases() {

        // Create an Account with no Cases

        Account acc = new Account(Name = 'No Case Account');

        insert acc;
 
        // Call the method

        Test.startTest();

        List<Case> results = CaseController.getCases(acc.Id);

        Test.stopTest();
 
        // Assertions

        System.assertEquals(0, results.size(), 'No cases should be returned');

    }

}