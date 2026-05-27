public class CaseFeedFileQueueable implements Queueable, Database.AllowsCallouts {
    Id caseId;
    String fileUrl;
    String fileName;

    public CaseFeedFileQueueable(Id caseId, String fileUrl, String fileName) {
        this.caseId = caseId;
        this.fileUrl = fileUrl;
        this.fileName = fileName;
    }

    public void execute(QueueableContext qc) {
        try {
            // Step 1: Download the file
            HttpRequest req = new HttpRequest();
            req.setEndpoint(fileUrl);
            req.setMethod('GET');
            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != 200) {
                System.debug('Failed to download file: ' + res.getStatusCode());
                return;
            }

            Blob fileBody = res.getBodyAsBlob();

            
            Attachment att = new Attachment();
            att.ParentId = caseId;
            att.Name = fileName;
            att.Body = fileBody;
            insert att;

            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = fileBody;
            cv.FirstPublishLocationId = caseId; 
            insert cv;


        } catch (Exception e) {
            System.debug('Error in CaseFeedFileQueueable: ' + e.getMessage());
        }
    }
}