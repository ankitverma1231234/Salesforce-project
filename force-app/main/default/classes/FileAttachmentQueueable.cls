public class FileAttachmentQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<CaseMedicalChatterCrate.FileAttachmentWrapper> fileWrappers;
    
    public FileAttachmentQueueable(List<CaseMedicalChatterCrate.FileAttachmentWrapper> fileWrappers) {
        this.fileWrappers = fileWrappers;
    }
    
    public void execute(QueueableContext context) {
        
        if (fileWrappers == null || fileWrappers.isEmpty()) {
            return;
        }
        
        List<ContentVersion> contentVersionsToInsert = new List<ContentVersion>();
        
        Integer processCount = Math.min(fileWrappers.size(), 100);
        
        for (Integer i = 0; i < processCount; i++) {
            CaseMedicalChatterCrate.FileAttachmentWrapper wrapper = fileWrappers[i];
            
            if (String.isBlank(wrapper.fileUrl) || String.isBlank(wrapper.filename)) {
                continue;
            }
            
            try {
                HttpRequest httpReq = new HttpRequest();
                httpReq.setEndpoint(wrapper.fileUrl);
                httpReq.setMethod('GET');
                httpReq.setTimeout(120000);
                
                httpReq.setHeader('Connection', 'keep-alive');
                httpReq.setHeader('Accept', '*/*');
                
                Http http = new Http();
                HttpResponse httpRes = http.send(httpReq);
                
                if (httpRes.getStatusCode() == 200) {
                    Blob fileBlob = httpRes.getBodyAsBlob();
                    
                    ContentVersion cv = new ContentVersion();
                    cv.Title = wrapper.filename;
                    cv.PathOnClient = wrapper.filename;
                    cv.VersionData = fileBlob;
                    cv.IsMajorVersion = true;
                    cv.FirstPublishLocationId = wrapper.caseId;
                    
                    contentVersionsToInsert.add(cv);
                    
                } else {
                    System.debug('Failed to download file: ' + wrapper.fileUrl + 
                               ' - Status: ' + httpRes.getStatusCode() + 
                               ' - ' + httpRes.getStatus());
                }
            } catch (Exception e) {
                System.debug('Error downloading file: ' + wrapper.fileUrl + 
                           ' - Error: ' + e.getMessage() +
                           ' - Stack: ' + e.getStackTraceString());
            }
        }
        
        // Insert ContentVersions (Files) in bulk
        if (!contentVersionsToInsert.isEmpty()) {
            try {
                insert contentVersionsToInsert;
            } catch (Exception e) {
                System.debug('Error inserting files: ' + e.getMessage() + 
                           ' - Stack: ' + e.getStackTraceString());
            }
        }
        
        // Chain another job if more files remain (100+ files)
        if (fileWrappers.size() > processCount) {
            List<CaseMedicalChatterCrate.FileAttachmentWrapper> remainingFiles = 
                new List<CaseMedicalChatterCrate.FileAttachmentWrapper>();
            
            for (Integer i = processCount; i < fileWrappers.size(); i++) {
                remainingFiles.add(fileWrappers[i]);
            }

            if (!remainingFiles.isEmpty()) {
                System.enqueueJob(new FileAttachmentQueueable(remainingFiles));
            }
        }
    }
}