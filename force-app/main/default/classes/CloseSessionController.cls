public class CloseSessionController {
    @AuraEnabled
    public static String closeSession(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('Session ID cannot be null.');
        }

        Message_Session__c session;
        try {
            session = [
                SELECT Id, Session_Status__c, Phone_Number__c
                FROM Message_Session__c
                WHERE Id = :sessionId
                LIMIT 1
            ];
        } catch (QueryException qe) {
            throw new AuraHandledException('Session not found: ' + qe.getMessage());
        }

        if (session.Session_Status__c == 'Closed') {
            return 'already_closed';
        }
        session.Session_Status__c = 'Closed';
        try {
            update session;
        } catch (DmlException de) {
            throw new AuraHandledException('Error closing session: ' + de.getMessage());
        }

        return 'Success';
    }
}