public class MetriportContentProcessor implements Queueable {
    
    private Id contentVersionId;
    
    public MetriportContentProcessor(Id contentVersionId) {
        this.contentVersionId = contentVersionId;
    }
    
    public void execute(QueueableContext context) {
        try {
            // Retrieve stored content
            ContentVersion cv = [
                SELECT VersionData, Title 
                FROM ContentVersion 
                WHERE Id = :contentVersionId 
                LIMIT 1
            ];
            
            String patientJson = cv.VersionData.toString();
            System.debug('Processing patient JSON. Length: ' + patientJson.length());
            
            // Process with your existing job
            System.enqueueJob(new AllergyJob(patientJson));
            
            // Chain other processors if needed
            // System.enqueueJob(new ImmunizationJob(patientJson));
            
        } catch (System.LimitException e) {
            System.debug('Still too large for single processing. Using batch.');
            // Fallback to batch processing
            //Database.executeBatch(new MetriportBatchProcessor(contentVersionId), 1);
            
        } catch (Exception e) {
            System.debug('Error in ContentProcessor: ' + e.getMessage());
        }
    }
}