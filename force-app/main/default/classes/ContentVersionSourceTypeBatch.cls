global class ContentVersionSourceTypeBatch implements Database.Batchable<SObject> {
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id,
            Source_Type__c,
            FirstPublishLocationId
            FROM   ContentVersion
            WHERE  Source_Type__c != null
            AND    Source_Type__c = 'Metriport'
        ]);
    }
    
    global void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        List<ContentVersion> recordsToUpdate = new List<ContentVersion>();
        
        for (ContentVersion cv : scope) {
            if (
                cv.FirstPublishLocationId != null &&
                String.valueOf(cv.FirstPublishLocationId).startsWith('001') &&
                cv.Source_Type__c == null
            ) {
                cv.Source_Type__c = cv.Source__c;
                recordsToUpdate.add(cv);
            }
        }
        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        System.debug('ContentVersion Source_Type__c batch update completed.');
    }
}