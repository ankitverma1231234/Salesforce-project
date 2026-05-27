public class CaseAutoCreateQueueablePortalUserActOnIt implements Queueable {
    
    private Set<Id> caseIds;
    
    public CaseAutoCreateQueueablePortalUserActOnIt(Set<Id> caseIds) {
        this.caseIds = caseIds;
    }
    
    public void execute(QueueableContext context) {
        List<Case> sourceCases = [
            SELECT Id,
                   AccountId,
                   ContactPhone,
                   ContactEmail,
                   Subject,
                   Description,
                   Priority,
                   Case_Type__c,ContactId,OwnerId
            FROM Case
            WHERE Id IN :caseIds
        ];
        
        /*List<Case> casesToInsert = new List<Case>();
        for (Case src : sourceCases) {
            Case newCase = new Case();
            newCase.AccountId    = src.AccountId;
            newCase.Subject      = src.Subject;
            newCase.Description  = src.Description;
            newCase.Status       = 'New';
            newCase.Priority     = 'Medium';
            newCase.ContactId= src.ContactId;
            newCase.Case_Type__c = src.Case_Type__c;
             newCase.OwnerId = src.OwnerId;
            casesToInsert.add(newCase);
        }
        
        if (!casesToInsert.isEmpty()) {
            insert casesToInsert;
        }*/
    }
}