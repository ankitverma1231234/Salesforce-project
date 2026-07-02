public class QuickBooksItemService {

    // ── DTOs ────────────────────────────────────────────────────────────────

    public class ItemRequest {
        public String  Name;
        public String  Sku;
        public String  Type = 'Service';
        public IncomeAccountRef IncomeAccountRef;
    }

    public class IncomeAccountRef {
        public String value;
    }

    public class ItemResult {
        public Boolean success;
        public String  qbItemId;
        public String  errorMessage;
        public Integer statusCode;
    }

    // ── Query QB item by SKU ─────────────────────────────────────────────────

    public static String queryItemBySku(String sku) {
        try {
            String query = 'SELECT Id, Name, Sku FROM Item WHERE Sku = \'' + sanitize(sku) + '\'';
            Map<String, Object> queryResp = runQuery(query);
            List<Object> items = (List<Object>) queryResp.get('Item');
            if (items != null && !items.isEmpty()) {
                return (String) ((Map<String, Object>) items[0]).get('Id');
            }
        } catch (Exception e) {
            System.debug('QB item SKU query failed: ' + e.getMessage());
        }
        return null;
    }

    // ── Query QB item by Name (fallback when SKU not set in QB) ──────────────

    public static String queryItemByName(String name) {
        try {
            String query = 'SELECT Id, Name FROM Item WHERE Name = \'' + sanitize(name) + '\'';
            Map<String, Object> queryResp = runQuery(query);
            List<Object> items = (List<Object>) queryResp.get('Item');
            if (items != null && !items.isEmpty()) {
                return (String) ((Map<String, Object>) items[0]).get('Id');
            }
        } catch (Exception e) {
            System.debug('QB item Name query failed: ' + e.getMessage());
        }
        return null;
    }

    // ── Create new QB item ────────────────────────────────────────────────────

    public static ItemResult createItem(String name, String sku) {
        ItemResult result = new ItemResult();
        try {
            ItemRequest req      = new ItemRequest();
            req.Name             = name;
            req.Sku              = sku;
            req.IncomeAccountRef = new IncomeAccountRef();
            req.IncomeAccountRef.value = QuickBooksConfig.getDefaultIncomeAccountId();

            String endpoint = QuickBooksConfig.NAMED_CREDENTIAL
                             + '/v3/company/' + QuickBooksConfig.getCompanyId()
                             + '/item?minorversion=' + QuickBooksConfig.API_VERSION;

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(endpoint);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setHeader('Accept', 'application/json');
            httpReq.setBody(JSON.serialize(req, true));

            HttpResponse res  = new Http().send(httpReq);
            result.statusCode = res.getStatusCode();

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                result.success = true;
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> item = (Map<String, Object>) body.get('Item');
                result.qbItemId = (String) item.get('Id');
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

    // ── Shared query runner ───────────────────────────────────────────────────

    private static Map<String, Object> runQuery(String query) {
        String endpoint = QuickBooksConfig.NAMED_CREDENTIAL
                         + '/v3/company/' + QuickBooksConfig.getCompanyId()
                         + '/query?query=' + EncodingUtil.urlEncode(query, 'UTF-8')
                         + '&minorversion=' + QuickBooksConfig.API_VERSION;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (Map<String, Object>) body.get('QueryResponse');
        }
        return new Map<String, Object>();
    }

    private static String sanitize(String input) {
        return input == null ? '' : input.replace('\'', '\\\'');
    }
}