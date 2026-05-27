@isTest(SeeAllData=true)
public class ResendApprovalEmailControllerTest {
    
    private static Account createPersonAccount(String lastName, String email) {
        RecordType personRT = [
            SELECT Id 
            FROM   RecordType 
            WHERE  SObjectType = 'Account' 
            AND    IsPersonType = true 
            LIMIT  1
        ];
        Account pa = new Account(
            LastName      = lastName,
            RecordTypeId  = personRT.Id,
            PersonEmail   = email
        );
        insert pa;
        return pa;
    }
    
    private static Account_Head_Relationship__c createRelationship(
        Id authorizedAccountId,
        String status
    ) {
        Account_Head_Relationship__c rel = new Account_Head_Relationship__c(
            Authorized_Account_Access__c = authorizedAccountId,
            Portal_Access_Status__c      = status
        );
        insert rel;
        return rel;
    }
    
    
    @isTest
    static void testResendEmail_NullRecordId_ThrowsException() {
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            ResendApprovalEmailController.resendEmail(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
                            'AuraHandledException should be thrown when recordId is null');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // TEST 2: Invalid / Non-Existent Record Id → throws AuraHandledException
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testResendEmail_RecordNotFound_ThrowsException() {
        // Generate a syntactically valid but non-existent ID
        Id fakeId = 'a0X000000000001AAA';
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            ResendApprovalEmailController.resendEmail(fakeId);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
                            'AuraHandledException should be thrown when record is not found');
    }
    
    @isTest
    static void testResendEmail_StatusNotPending_ThrowsException() {
        Account personAcc = createPersonAccount('StatusTest', 'statustest@example.com');
        Account_Head_Relationship__c rel = createRelationship(personAcc.Id, 'Approved'); // ✅ Valid value
        
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            ResendApprovalEmailController.resendEmail(rel.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown,
                            'AuraHandledException should be thrown when status is Approved');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // TEST 4: Status = 'Pending' but No Email on Related Record → throws Exception
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testResendEmail_NoEmailOnRelatedRecord_ThrowsException() {
        // Create Person Account with blank email
        Account personAcc = createPersonAccount('NoEmailTest', '');
        Account_Head_Relationship__c rel = createRelationship(personAcc.Id, 'Pending');
        
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            ResendApprovalEmailController.resendEmail(rel.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
                            'AuraHandledException should be thrown when PersonEmail is blank');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // TEST 5: Happy Path → Status = 'Pending' + Valid Email → Emails Sent
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testResendEmail_Success_EmailsSent() {
        Account personAcc = createPersonAccount('SuccessTest', 'success@example.com');
        Account_Head_Relationship__c rel = createRelationship(personAcc.Id, 'Pending');
        
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            ResendApprovalEmailController.resendEmail(rel.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(false, exceptionThrown, 
                            'No exception should be thrown for a valid Pending record with email');
    }
}