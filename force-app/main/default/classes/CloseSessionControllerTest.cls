@IsTest
public class CloseSessionControllerTest {

    @TestSetup
    static void setupData() {
        Message_Session__c session = new Message_Session__c(
            Session_Status__c = 'Open',
            Phone_Number__c   = '1234567890'
        );
        insert session;
    }

    // ─── Test 1: Null Session ID ───────────────────────────────────────────────
    @IsTest
    static void testNullSessionId() {
        Test.startTest();
        try {
            CloseSessionController.closeSession(null);
            System.assert(false, 'Expected AuraHandledException was not thrown.');
        } catch (AuraHandledException e) {
            System.assertEquals(
                'Script-thrown exception',
                e.getMessage(),
                'AuraHandledException should be thrown for null session ID.'
            );
        }
        Test.stopTest();
    }

    // ─── Test 2: Session Already Closed ───────────────────────────────────────
    @IsTest
    static void testAlreadyClosedSession() {
        Message_Session__c session = [
            SELECT Id FROM Message_Session__c LIMIT 1
        ];

        session.Session_Status__c = 'Closed';
        update session;

        Test.startTest();
        String result = CloseSessionController.closeSession(session.Id);
        Test.stopTest();

        System.assertEquals(
            'already_closed',
            result,
            'Should return already_closed when session is already closed.'
        );
    }

    // ─── Test 3: Successful Session Close ─────────────────────────────────────
    @IsTest
    static void testSuccessfulCloseSession() {
        Message_Session__c session = [
            SELECT Id, Session_Status__c FROM Message_Session__c LIMIT 1
        ];

        System.assertEquals(
            'Open',
            session.Session_Status__c,
            'Session should be Open before closing.'
        );

        Test.startTest();
        String result = CloseSessionController.closeSession(session.Id);
        Test.stopTest();

        // Verify return value
        System.assertEquals(
            'Success',
            result,
            'Should return Success after closing session.'
        );

        // Verify session status updated to Closed
        Message_Session__c updatedSession = [
            SELECT Session_Status__c FROM Message_Session__c WHERE Id = :session.Id
        ];
        System.assertEquals(
            'Closed',
            updatedSession.Session_Status__c,
            'Session status should be Closed after closeSession is called.'
        );
    }

    @IsTest
    static void testInvalidSessionId() {
        Id fakeId = '000000000000000000';

        Test.startTest();
        try {
            CloseSessionController.closeSession(fakeId);
            System.assert(false, 'Expected AuraHandledException was not thrown.');
        } catch (AuraHandledException e) {
            System.assertEquals(
                'Script-thrown exception',
                e.getMessage(),
                'AuraHandledException should be thrown for invalid session ID.'
            );
        }
        Test.stopTest();
    }
}