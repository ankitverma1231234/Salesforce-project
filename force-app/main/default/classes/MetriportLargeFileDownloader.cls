public class MetriportLargeFileDownloader implements Queueable, Database.AllowsCallouts {
    
    private String fileUrl;
    private Integer retryCount;
    
    public MetriportLargeFileDownloader(String fileUrl) {
        this.fileUrl = fileUrl;
        this.retryCount = 0;
    }
    
    public MetriportLargeFileDownloader(String fileUrl, Integer retryCount) {
        this.fileUrl = fileUrl;
        this.retryCount = retryCount;
    }
    
    public void execute(QueueableContext context) {
        try {
            System.debug('Attempting to download file from: ' + fileUrl);
            
            Blob fileContent = downloadFile(fileUrl);
            
            if (fileContent != null) {
                System.debug('Downloaded file successfully. Size: ' + fileContent.size() + ' bytes');
                
                Id contentVersionId = storeAsContentVersion(fileContent);
                
                if (contentVersionId != null) {
                    System.enqueueJob(new MetriportContentProcessor(contentVersionId));
                }
            } else {
                System.debug('Failed to download file');
                handleDownloadFailure();
            }
            
        } catch (System.LimitException e) {
            System.debug('Heap limit exceeded even in Queueable: ' + e.getMessage());
           // System.enqueueJob(new MetriportStreamingDownloader(fileUrl));
            
        } catch (Exception e) {
            System.debug('Error downloading file: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            handleDownloadFailure();
        }
    }
    
    private Blob downloadFile(String url) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(url);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            req.setCompressed(true);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() == 200) {
                return res.getBodyAsBlob();
            }
            
            System.debug('Download failed: ' + res.getStatusCode() + ' - ' + res.getStatus());
            return null;
            
        } catch (System.CalloutException e) {
            System.debug('Callout exception in Queueable: ' + e.getMessage());
            throw e;
        }
    }
    
    private Id storeAsContentVersion(Blob fileContent) {
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Metriport_' + DateTime.now().getTime();
            cv.PathOnClient = 'patient_data.json';
            cv.VersionData = fileContent;
            cv.FirstPublishLocationId = '001DP000026MeQ5YAK';
            cv.URL__c = fileUrl; // Store full URL in custom field
            insert cv;
            
            System.debug('Stored ContentVersion: ' + cv.Id);
            return cv.Id;
            
            
            
        } catch (Exception e) {
            System.debug('Error storing ContentVersion: ' + e.getMessage());
            return null;
        }
    }
    
    private void handleDownloadFailure() {
        if (retryCount < 2) {
           // System.enqueueJob(new MetriportLargeFileDownloader(fileUrl, retryCount + 1));
            System.debug('Retrying download. Attempt: ' + (retryCount + 1));
        } else {
            System.debug('Max retries reached. Creating error log.');
            createErrorLog();
        }
    }
    
    private void createErrorLog() {
        System.debug('CRITICAL: Failed to download Metriport file after retries: ' + fileUrl);
        // TODO: Insert into custom error logging object
    }
}