public class SessionTimeoutBatch implements Database.Batchable<Sobject> {
    public Database.QueryLocator start(Database.BatchableContext BC){
        DateTime now = DateTime.now();
        
        return Database.getQueryLocator([
            SELECT Id, Phone_Number__c, Start_Time__c, 
            End_Time__c, Session_Status__c
            FROM Message_Session__c
            WHERE Session_Status__c = 'Open'
            AND End_Time__c <= :now
        ]);
        
    }
    
    public void execute(Database.BatchableContext bc, List<Message_Session__c> expiredSessions){
        List<Message_Session__c> sessionsToClose = new List<Message_Session__c>();
        for(Message_Session__c session : expiredSessions){
            sessionsToClose.add( new Message_Session__c(Id = session.Id,Session_Status__c = 'Closed'));
        }
        if(!sessionsToClose.IsEmpty()){
            Update sessionsToClose;
        }
        
    }
    Public void finish(Database.BatchableContext bc){
        System.debug('SessionTimeoutBatch completed at: ' + DateTime.now());
    }
    
}