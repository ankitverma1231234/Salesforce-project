public without sharing class DeleteAccountHeadRelationshipQueueable Implements Queueable {
    private static final Integer BATCH_SIZE = 200;
    
    private List<String> relationshipIds;   
    private Integer      startIndex;       
    
    public DeleteAccountHeadRelationshipQueueable(List<String> ids) {
        this(ids, 0);
    }
    
    private DeleteAccountHeadRelationshipQueueable(List<String> ids, Integer startIdx) {
        this.relationshipIds = ids;
        this.startIndex      = startIdx;
    }
    
    public void execute(QueueableContext context) {
        
        if (relationshipIds == null || relationshipIds.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                         'DeleteAccountHeadRelationshipQueueable: no IDs provided. Nothing to delete.');
            return;
        }
        
        Integer endIndex = Math.min(startIndex + BATCH_SIZE, relationshipIds.size());
        
        List<String> batchIds = new List<String>();
        for (Integer i = startIndex; i < endIndex; i++) {
            batchIds.add(relationshipIds[i]);
        }
        
        System.debug('DeleteAccountHeadRelationshipQueueable: processing IDs ' +
                     startIndex + ' to ' + (endIndex - 1) +
                     ' of ' + relationshipIds.size());
        
        try {
            List<Account_Head_Relationship__c> toDelete = [
                SELECT Id
                FROM   Account_Head_Relationship__c
                WHERE  Id IN :batchIds
            ];
            
            if (!toDelete.isEmpty()) {
                List<Database.DeleteResult> results = Database.delete(toDelete, false);
            } else {
                System.debug(LoggingLevel.WARN,
                             'DeleteAccountHeadRelationshipQueueable: none of the supplied IDs ' +
                             'matched existing Account_Head_Relationship__c records. IDs: ' + batchIds);
            }
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                         'DeleteAccountHeadRelationshipQueueable error: ' + ex.getMessage() +
                         ' | Stack: ' + ex.getStackTraceString());
        }
        
    }
    
}