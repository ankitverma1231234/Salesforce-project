public class QuickBooksInvoicePdfQueueable implements Queueable, Database.AllowsCallouts {

    private Id     oppId;
    private String qbInvoiceId;

    public QuickBooksInvoicePdfQueueable(Id oppId, String qbInvoiceId) {
        this.oppId       = oppId;
        this.qbInvoiceId = qbInvoiceId;
    }

    public void execute(QueueableContext ctx) {
        try {
            // Step 1 — fetch PDF bytes from QB
            Blob pdfBlob = fetchInvoicePdf(qbInvoiceId);
            if (pdfBlob == null) {
                logError('PDF fetch returned null for QB Invoice Id: ' + qbInvoiceId);
                return;
            }

            // Step 2 — create ContentVersion (file)
            ContentVersion cv  = new ContentVersion();
            cv.Title           = 'Invoice_' + qbInvoiceId + '.pdf';
            cv.PathOnClient    = 'Invoice_' + qbInvoiceId + '.pdf';
            cv.VersionData     = pdfBlob;
            cv.IsMajorVersion  = true;
            insert cv;

            // Step 3 — get ContentDocumentId
            ContentVersion insertedCv = [
                SELECT ContentDocumentId
                FROM   ContentVersion
                WHERE  Id = :cv.Id
                LIMIT  1
            ];

            // Step 4 — link ContentDocument to Opportunity
            insert new ContentDocumentLink(
                ContentDocumentId = insertedCv.ContentDocumentId,
                LinkedEntityId    = oppId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            );

            System.debug('Invoice PDF stored successfully for Opp: ' + oppId);

        } catch (Exception e) {
            logError(e.getMessage());
        }
    }

    // ── Fetch PDF from QB ─────────────────────────────────────────────────────

    private Blob fetchInvoicePdf(String qbInvoiceId) {
        String endpoint = QuickBooksConfig.NAMED_CREDENTIAL
                        + '/v3/company/' + QuickBooksConfig.getCompanyId()
                        + '/invoice/' + qbInvoiceId
                        + '/pdf?minorversion=' + QuickBooksConfig.API_VERSION;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/pdf');

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            return res.getBodyAsBlob();
        }

        System.debug('PDF fetch failed. Status: ' + res.getStatusCode()
                   + ' Body: ' + res.getBody());
        return null;
    }

    private void logError(String message) {
        try {
            insert new Error_Log__c(
                Record_External_Id__c = (String) oppId,
                Error_Message__c      = message,
                Context__c            = 'QuickBooksInvoicePdfQueueable.execute',
                Stack_Trace__c        = 'OpportunityId: ' + oppId
                                      + ' | QB Invoice Id: ' + qbInvoiceId
            );
        } catch (Exception e) {
            System.debug('Error log insert failed: ' + e.getMessage());
        }
    }
}