public class GeneratePdfQueueable implements Queueable, Database.AllowsCallouts {

    private String recordId;
    private String requestBody;
    private String fileName;

    public GeneratePdfQueueable(
        String recordId,
        String requestBody,
        String fileName
    ){
        this.recordId = recordId;
        this.requestBody = requestBody;
        this.fileName = fileName;
    }

    public void execute(QueueableContext qc){

        try{

            HttpRequest req = new HttpRequest();
            req.setEndpoint(Label.PDF_Generator_API_Endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type','application/json');
            req.setTimeout(120000);
            req.setBody(requestBody);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if(res.getStatusCode() != 200){
                throw new CalloutException(
                    'PDF generation failed: ' +
                    res.getStatusCode()
                );
            }

            Blob pdfBlob = res.getBodyAsBlob();

            ContentVersion cv = new ContentVersion();
            cv.Title = fileName + '.pdf';
            cv.PathOnClient = fileName + '.pdf';
            cv.VersionData = pdfBlob;
            cv.FirstPublishLocationId = recordId;
            cv.IsMajorVersion = true;

            insert cv;

            System.debug('PDF attached successfully');

            Case c = [
                SELECT Id,
                       Account.Name,
                       Account.Metriport_Patient_Id__c
                FROM Case
                WHERE Id = :recordId
                LIMIT 1
            ];

            if(String.isBlank(
                c.Account.Metriport_Patient_Id__c
            )){
                System.debug(
                    'Metriport Patient Id missing'
                );
                return;
            }
/*if (!Test.isRunningTest()) {
            System.enqueueJob(new MetriportUploadQueueable(c.Account.Metriport_Patient_Id__c,c.Account.Name, pdfBlob,fileName + '.pdf', 'pdf', 'Clinical Summary', '34133-9', 'Summarization of Episode Note','Hospital',String.valueOf(Date.today()), c.Id));
}*/

            System.debug(
                'MetriportUploadQueueable queued'
            );

        }catch(Exception e){

            System.debug(
                'GeneratePdfQueueable Error: ' +
                e.getMessage()
            );

            throw e;
        }
    }
}