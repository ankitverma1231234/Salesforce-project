public class CaseChatterFileQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<CaseMedicalChatterCrate.FileAttachmentWrapper> fileWrappers;
    
    public CaseChatterFileQueueable(List<CaseMedicalChatterCrate.FileAttachmentWrapper> wrappers) {
        this.fileWrappers = wrappers;
    }
    
    public void execute(QueueableContext qc) {
        System.debug('=== CaseChatterFileQueueable Started ===');
        
        if (fileWrappers == null || fileWrappers.isEmpty()) {
            System.debug('No file wrappers to process');
            return;
        }
        
        for (CaseMedicalChatterCrate.FileAttachmentWrapper wrapper : fileWrappers) {
            System.debug('Processing: Case=' + wrapper.caseId + ', File=' + wrapper.filename);
            
            if (wrapper.caseId == null) {
                System.debug('ERROR: Case ID is null, skipping');
                continue;
            }
            
            processWrapper(wrapper);
        }
        
        System.debug('=== CaseChatterFileQueueable Completed ===');
    }
    
    private void processWrapper(CaseMedicalChatterCrate.FileAttachmentWrapper wrapper) {
        try {
            // Step 1: Download file from URL
            if (String.isBlank(wrapper.fileUrl) || String.isBlank(wrapper.filename)) {
                System.debug('No file URL or filename provided');
                
                // If no file but has message body, create text-only post
                if (!String.isBlank(wrapper.messageBody)) {
                    createTextOnlyPost(wrapper);
                }
                return;
            }
            
            System.debug('Downloading file from: ' + wrapper.fileUrl);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(wrapper.fileUrl);
            req.setMethod('GET');
            req.setTimeout(60000);
            
            HttpResponse res = new Http().send(req);
            
            if (res.getStatusCode() != 200) {
                System.debug('Failed to download file: ' + res.getStatusCode());
                return;
            }
            
            System.debug('File downloaded successfully. Size: ' + res.getBodyAsBlob().size());
            
            // Step 2: Create ContentVersion
            ContentVersion cv = new ContentVersion();
            cv.Title = wrapper.filename;
            cv.PathOnClient = wrapper.filename;
            cv.VersionData = res.getBodyAsBlob();
            insert cv;
            
            System.debug('ContentVersion created: ' + cv.Id);
            
            // Step 3: Create FeedItem (Chatter post) with file attached
            // IMPORTANT: Do NOT set Body field - this causes "read-only" error in Queueable context
            FeedItem post = new FeedItem(
                ParentId = wrapper.caseId,
                Type = 'ContentPost',
                RelatedRecordId = cv.Id
            );
            insert post;
            
            System.debug('SUCCESS: FeedItem created with file attachment. Id: ' + post.Id);
            
            // Step 4: If there's a message body, add it as a comment on the post
            if (!String.isBlank(wrapper.messageBody)) {
                addCommentToFeedItem(post.Id, wrapper.messageBody);
            }
            
        } catch (Exception e) {
            System.debug('Error in processWrapper: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
    }
    
    private void createTextOnlyPost(CaseMedicalChatterCrate.FileAttachmentWrapper wrapper) {
        try {
            System.debug('Creating text-only FeedItem...');
            
            FeedItem post = new FeedItem(
                ParentId = wrapper.caseId,
                Type = 'TextPost',
                Body = wrapper.messageBody
            );
            insert post;
            
            System.debug('SUCCESS: Text-only FeedItem created. Id: ' + post.Id);
            
        } catch (Exception e) {
            System.debug('Error creating text-only post: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
    }
    
    private void addCommentToFeedItem(Id feedItemId, String messageBody) {
        try {
            System.debug('Adding comment to FeedItem...');
            
            FeedComment comment = new FeedComment(
                FeedItemId = feedItemId,
                CommentBody = messageBody
            );
            insert comment;
            
            System.debug('SUCCESS: FeedComment added. Id: ' + comment.Id);
            
        } catch (Exception e) {
            System.debug('Error adding comment: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
    }
}