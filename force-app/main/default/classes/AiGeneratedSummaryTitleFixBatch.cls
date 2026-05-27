public class AiGeneratedSummaryTitleFixBatch implements Database.Batchable<SObject> {
    
    private Boolean sendFileToPortal;
    
    public AiGeneratedSummaryTitleFixBatch(Boolean sendFileToPortal) {
        this.sendFileToPortal = sendFileToPortal;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Title
            FROM ContentVersion
            WHERE Source__c = 'metriport'
            AND Send_File_to_Portal__c = true
            AND FirstPublishLocationId IN (SELECT Id FROM Account)
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        
        ContentVersion cv = scope[0];
        
        List<ContentVersion> relatedRecords = [
            SELECT Id, Related_File__c, Send_File_to_Portal__c
            FROM ContentVersion
            WHERE Related_File__c = :cv.Id
        ];
        
        if (relatedRecords.isEmpty()) return;
        
        for (ContentVersion related : relatedRecords) {
            related.Send_File_to_Portal__c = sendFileToPortal;
        }
        
        try {
            update relatedRecords;
        } catch (DmlException e) {
            System.debug('DML Error: ' + e.getMessage());
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('AiGeneratedSummaryTitleFixBatch completed. Send_File_to_Portal__c set to: ' + sendFileToPortal);
    }
}