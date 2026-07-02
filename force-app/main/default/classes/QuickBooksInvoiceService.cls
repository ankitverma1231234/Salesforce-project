public class QuickBooksInvoiceService {

    // ── DTOs ─────────────────────────────────────────────────────────────────

    public class InvoiceRequest {
        public List<InvoiceLine> Line;
        public QBRef             CustomerRef;
        public String            TxnDate;
        public String            PrivateNote;
        public String            Id;
        public String            SyncToken;
    }

    public class InvoiceLine {
        public String            DetailType = 'SalesItemLineDetail';
        public Decimal           Amount;
        public String            Description;
        public SalesItemLineDetail SalesItemLineDetail;
    }

    public class SalesItemLineDetail {
        public QBRef   ItemRef;
        public Decimal Qty;
        public Decimal UnitPrice;
    }

    public class QBRef {
        public String value;
    }

    public class InvoiceResponse {
        public Boolean success;
        public String  qbInvoiceId;
        public String  syncToken;
        public String  errorMessage;
        public Integer statusCode;
        public String  operation;
    }

    // ── Main entry point ─────────────────────────────────────────────────────

    public static InvoiceResponse upsertInvoice(Opportunity opp) {
        InvoiceResponse result;

        if (String.isNotBlank(opp.QB_Invoice_Id__c)) {
            result = updateInvoice(opp);
        } else {
            result = createInvoice(opp);
        }

        return result;
    }

    // ── Create ───────────────────────────────────────────────────────────────

    private static InvoiceResponse createInvoice(Opportunity opp) {
        InvoiceRequest payload = buildPayload(opp, null, null);
        InvoiceResponse result = callout(payload);
        if (result.success) result.operation = 'created';
        return result;
    }

    // ── Update ───────────────────────────────────────────────────────────────

    private static InvoiceResponse updateInvoice(Opportunity opp) {
        String syncToken       = fetchSyncToken(opp.QB_Invoice_Id__c);
        InvoiceRequest payload = buildPayload(opp, opp.QB_Invoice_Id__c, syncToken);
        InvoiceResponse result = callout(payload);
        if (result.success) result.operation = 'updated';
        return result;
    }

    // ── Build payload ─────────────────────────────────────────────────────────

    private static InvoiceRequest buildPayload(Opportunity opp, String qbId, String syncToken) {
        InvoiceRequest req  = new InvoiceRequest();
        req.TxnDate         = String.valueOf(opp.CloseDate);
        req.PrivateNote     = opp.Name;
        req.Line            = buildLines(opp.OpportunityLineItems);

        req.CustomerRef         = new QBRef();
        req.CustomerRef.value   = opp.Account.QB_Customer_Id__c;

        if (String.isNotBlank(qbId)) {
            req.Id        = qbId;
            req.SyncToken = syncToken ?? '0';
        }

        return req;
    }

    // ── Build line items ──────────────────────────────────────────────────────

    private static List<InvoiceLine> buildLines(List<OpportunityLineItem> olis) {
        if (olis == null || olis.isEmpty()) {
            throw new QuickBooksConfig.QuickBooksException(
                'Opportunity has no line items — cannot create invoice'
            );
        }

        List<InvoiceLine> lines = new List<InvoiceLine>();

        for (OpportunityLineItem oli : olis) {
            if (String.isBlank(oli.Product2.QB_Item_Id__c)) {
                throw new QuickBooksConfig.QuickBooksException(
                    'Product missing QB_Item_Id__c: ' + oli.Product2.Name
                    + ' — run product sync batch first'
                );
            }

            SalesItemLineDetail detail = new SalesItemLineDetail();
            detail.Qty                 = oli.Quantity;
            detail.UnitPrice           = oli.UnitPrice;
            detail.ItemRef             = new QBRef();
            detail.ItemRef.value       = oli.Product2.QB_Item_Id__c;

            InvoiceLine line           = new InvoiceLine();
            line.Amount                = oli.TotalPrice;
            line.Description           = oli.Product2.Description;
            line.SalesItemLineDetail   = detail;

            lines.add(line);
        }

        return lines;
    }

    // ── Fetch SyncToken ───────────────────────────────────────────────────────

    private static String fetchSyncToken(String qbInvoiceId) {
        try {
            String endpoint = QuickBooksConfig.NAMED_CREDENTIAL
                            + '/v3/company/' + QuickBooksConfig.getCompanyId()
                            + '/invoice/' + qbInvoiceId
                            + '?minorversion=' + QuickBooksConfig.API_VERSION;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> body    = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> invoice = (Map<String, Object>) body.get('Invoice');
                return (String) invoice.get('SyncToken');
            }
        } catch (Exception e) {
            System.debug('SyncToken fetch failed: ' + e.getMessage());
        }
        return '0';
    }

    // ── Callout ───────────────────────────────────────────────────────────────

    private static InvoiceResponse callout(InvoiceRequest payload) {
        InvoiceResponse result = new InvoiceResponse();
        try {
            String endpoint = QuickBooksConfig.NAMED_CREDENTIAL
                            + '/v3/company/' + QuickBooksConfig.getCompanyId()
                            + '/invoice?minorversion=' + QuickBooksConfig.API_VERSION;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setBody(JSON.serialize(payload, true));

            HttpResponse res  = new Http().send(req);
            result.statusCode = res.getStatusCode();

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                result.success              = true;
                Map<String, Object> body    = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> invoice = (Map<String, Object>) body.get('Invoice');
                result.qbInvoiceId          = (String) invoice.get('Id');
                result.syncToken            = (String) invoice.get('SyncToken');
            } else {
                result.success      = false;
                result.errorMessage = res.getBody();
            }
        } catch (Exception e) {
            result.success      = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }
}