public class MetriportDocumentDownloadQueueable
    implements Queueable, Database.AllowsCallouts {
    private List<Id> docIds;
    public MetriportDocumentDownloadQueueable(List<Id> docIds) {
        this.docIds = docIds == null ? new List<Id>() : new List<Id>(docIds);
    }
    public void execute(QueueableContext context) {
        if (docIds == null || docIds.isEmpty()) return;
        Id docId = docIds.remove(0);
        if (docId == null) return;
        try {
            downloadAndSaveDocument(docId);
        } catch (Exception e) {
            System.debug('Error downloading document ' + docId + ': ' + e.getMessage());
        }
        if (!docIds.isEmpty()) {
            System.enqueueJob(new MetriportDocumentDownloadQueueable(docIds));
        }
    }
    private void downloadAndSaveDocument(Id docId) {
        if (docId == null) return;
        Document_Reference__c docRef;
        try {
            docRef = [
                SELECT Id, File_Name__c,Patient__c,Date__c,Service_Date_Time__c,Description__c,Organization_Name__c
                FROM Document_Reference__c
                WHERE Id = :docId
                LIMIT 1
            ];
        } catch (Exception e) {
            return;
        }
        if (docRef == null || String.isBlank(docRef.File_Name__c)) return;
        String fileName = docRef.File_Name__c.toLowerCase();
        Boolean isXml = fileName.endsWith('.xml');
        Metriport_Config__mdt meta;
        try {
            meta = [
                SELECT API_Key__c, Base_URL__c
                FROM Metriport_Config__mdt
                WHERE Active__c = true
                LIMIT 1
            ];
        } catch (Exception e) {
            return;
        }

        if (meta == null ||
            String.isBlank(meta.API_Key__c) ||
            String.isBlank(meta.Base_URL__c)) {
            return;
        }

        Http http = new Http();

        String endpoint = meta.Base_URL__c +
            '/medical/v1/document/download-url?fileName=' +
            EncodingUtil.urlEncode(docRef.File_Name__c, 'UTF-8');

        if (isXml) {
            endpoint += '&conversionType=pdf';
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('x-api-key', meta.API_Key__c);
        req.setTimeout(120000);

        HttpResponse res;
        try {
            res = http.send(req);
        } catch (CalloutException ce) {
            return;
        }

        if (res == null || res.getStatusCode() != 200 || String.isBlank(res.getBody())) {
            return;
        }

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        if (body == null || !body.containsKey('url')) return;

        String url = (String) body.get('url');
        if (String.isBlank(url)) return;

        req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(120000);

        try {
            res = http.send(req);
        } catch (CalloutException ce) {
            return;
        }

        if (res == null) return;

        Blob fileBlob = res.getBodyAsBlob();
        if (fileBlob == null) return;

        String finalFileName = isXml
            ? docRef.File_Name__c.replace('.xml', '.pdf')
            : docRef.File_Name__c;

        ContentVersion cv = new ContentVersion();
        cv.Title = docRef.Description__c;
        cv.PathOnClient = finalFileName;
        cv.VersionData = fileBlob;
        cv.FirstPublishLocationId = docRef.Patient__c;
        cv.Description = docRef.Description__c;
        cv.Service_Date_Time__c = docRef.Service_Date_Time__c;
        cv.Source_Type__c ='Metriport';
        cv.Send_File_to_Portal__c = true;
        cv.Organization_Name__c =docRef.Organization_Name__c;

        insert cv;

        // Kick off document processing pipeline
        //for Ai Naming and Ai Summary generation and Gdrive sync
        Document_Processing_Log__c log = new Document_Processing_Log__c();
        log.Content_Version_Id__c    = cv.Id;
        log.Is_Active__c             = true;
        log.Ready_for_Attachment__c  = true;
        insert log;
    }
}