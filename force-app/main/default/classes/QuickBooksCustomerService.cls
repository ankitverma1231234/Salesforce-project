public class QuickBooksCustomerService {

    // ── DTOs ────────────────────────────────────────────────────────────────

    public class CustomerRequest {
        public String      GivenName;
        public String      FamilyName;
        public String      MiddleName;
        public String      Suffix;
        public String      Title;
        public String      DisplayName;
        public String      FullyQualifiedName;
        public String      Notes;
        public String      Id;
        public String      SyncToken;
        public QBEmailAddr PrimaryEmailAddr;
        public QBPhone     PrimaryPhone;
        public QBBillAddr  BillAddr;
    }

    public class QBEmailAddr {
        public String Address;
    }

    public class QBPhone {
        public String FreeFormNumber;
    }

    public class QBBillAddr {
        public String Line1;
        public String City;
        public String CountrySubDivisionCode;
        public String PostalCode;
        public String Country;
    }

    public class CustomerResponse {
        public Boolean success;
        public String  qbCustomerId;
        public String  syncToken;
        public String  errorMessage;
        public Integer statusCode;
        public String  operation;
    }

    // ── Main entry point ─────────────────────────────────────────────────────
   @AuraEnabled
    public static CustomerResponse upsertCustomer(Id accountId) {
         System.debug('*** accountId = ' + accountId);
        Account acc = fetchAccount(accountId);
        CustomerResponse result;

        if (String.isNotBlank(acc.QB_Customer_Id__c)) {
            result = updateCustomer(acc);

        } else if (String.isNotBlank(acc.PersonEmail)) {
            String existingQBId = queryQBCustomerByEmail(acc.PersonEmail);
            if (String.isNotBlank(existingQBId)) {
                acc.QB_Customer_Id__c = existingQBId;
                result = updateCustomer(acc);
            } else {
                result = createCustomer(acc);
            }

        } else {
            result = createCustomer(acc);
        }

        if (result.success) {
            writeBackToAccount(acc, result);
        } else {
            logError(accountId, acc.PersonEmail, result);
        }

        return result;
    }

    // ── Create ───────────────────────────────────────────────────────────────

    private static CustomerResponse createCustomer(Account acc) {
        CustomerRequest payload  = buildPayload(acc, null, null);
        CustomerResponse result  = callout(payload);
        if (result.success) result.operation = 'created';
        return result;
    }

    // ── Update ───────────────────────────────────────────────────────────────

    private static CustomerResponse updateCustomer(Account acc) {
        String syncToken         = fetchQBSyncToken(acc.QB_Customer_Id__c);
        CustomerRequest payload  = buildPayload(acc, acc.QB_Customer_Id__c, syncToken);
        CustomerResponse result  = callout(payload);
        if (result.success) result.operation = 'updated';
        return result;
    }

    // ── Query QB by email ────────────────────────────────────────────────────

    private static String queryQBCustomerByEmail(String email) {
        try {
            String query    = 'SELECT * FROM Customer WHERE PrimaryEmailAddr = \''
                            + email + '\'';
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
                Map<String, Object> body      = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> queryResp = (Map<String, Object>) body.get('QueryResponse');
                List<Object> customers        = (List<Object>) queryResp.get('Customer');
                if (customers != null && !customers.isEmpty()) {
                    Map<String, Object> customer = (Map<String, Object>) customers[0];
                    return (String) customer.get('Id');
                }
            }
        } catch (Exception e) {
            System.debug('QB email query failed: ' + e.getMessage());
        }
        return null;
    }

    // ── Fetch SyncToken ──────────────────────────────────────────────────────

    private static String fetchQBSyncToken(String qbCustomerId) {
        try {
            String endpoint = QuickBooksConfig.NAMED_CREDENTIAL
                            + '/v3/company/' + QuickBooksConfig.getCompanyId()
                            + '/customer/' + qbCustomerId
                            + '?minorversion=' + QuickBooksConfig.API_VERSION;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> body     = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> customer = (Map<String, Object>) body.get('Customer');
                return (String) customer.get('SyncToken');
            }
        } catch (Exception e) {
            System.debug('QB SyncToken fetch failed: ' + e.getMessage());
        }
        return '0';
    }

    // ── Write back ───────────────────────────────────────────────────────────

    private static void writeBackToAccount(Account acc, CustomerResponse result) {
        update new Account(
            Id                = acc.Id,
            QB_Customer_Id__c = result.qbCustomerId,
            Sync_Token__c = result.syncToken
        );
    }

    // ── Error log ────────────────────────────────────────────────────────────

    private static void logError(Id accountId, String email, CustomerResponse result) {
        try {
            insert new Error_Log__c(
                Record_External_Id__c = (String) accountId,
                Error_Message__c      = result.errorMessage,
                Context__c            = 'QuickBooksCustomerService.upsertCustomer',
                Stack_Trace__c        = 'AccountId: ' + accountId
                                      + ' | Email: ' + email
                                      + ' | StatusCode: ' + result.statusCode
            );
        } catch (Exception e) {
            System.debug('Error logging failed: ' + e.getMessage());
        }
    }

    // ── SOQL ─────────────────────────────────────────────────────────────────

    private static Account fetchAccount(Id accountId) {
        List<Account> records = [
            SELECT  Id, FirstName, LastName, MiddleName, Suffix, PersonTitle,
                    PersonEmail, PersonMobilePhone,
                    Additional_Notes_Comments__c,
                    PersonMailingStreet, PersonMailingCity,
                    PersonMailingStateCode, PersonMailingPostalCode,
                    PersonMailingCountry,
                    QB_Customer_Id__c
            FROM    Account
            WHERE   Id = :accountId 
            LIMIT   1
        ];
        if (records.isEmpty()) {
            throw new QuickBooksConfig.QuickBooksException(
                'Account not found or not a Person Account: ' + accountId
            );
        }
        return records[0];
    }

    // ── Build payload ────────────────────────────────────────────────────────

    private static CustomerRequest buildPayload(Account acc, String qbId, String syncToken) {
        CustomerRequest req    = new CustomerRequest();
        req.GivenName          = acc.FirstName;
        req.FamilyName         = acc.LastName;
        req.MiddleName         = acc.MiddleName;
        req.Suffix             = acc.Suffix;
        req.Title              = acc.PersonTitle;
        req.DisplayName        = ((acc.FirstName ?? '') + ' ' + (acc.LastName ?? '')).trim();
        req.FullyQualifiedName = req.DisplayName;
        req.Notes              = acc.Additional_Notes_Comments__c;

        if (String.isNotBlank(qbId)) {
            req.Id        = qbId;
            req.SyncToken = syncToken ?? '0';
        }

        if (String.isNotBlank(acc.PersonEmail)) {
            QBEmailAddr email    = new QBEmailAddr();
            email.Address        = acc.PersonEmail;
            req.PrimaryEmailAddr = email;
        }

        if (String.isNotBlank(acc.PersonMobilePhone)) {
            QBPhone phone        = new QBPhone();
            phone.FreeFormNumber = acc.PersonMobilePhone;
            req.PrimaryPhone     = phone;
        }

        if (String.isNotBlank(acc.PersonMailingStreet)) {
            QBBillAddr addr             = new QBBillAddr();
            addr.Line1                  = acc.PersonMailingStreet;
            addr.City                   = acc.PersonMailingCity;
            addr.CountrySubDivisionCode = acc.PersonMailingStateCode;
            addr.PostalCode             = acc.PersonMailingPostalCode;
            addr.Country                = acc.PersonMailingCountry;
            req.BillAddr                = addr;
        }

        return req;
    }

    // ── Callout ──────────────────────────────────────────────────────────────

    private static CustomerResponse callout(CustomerRequest payload) {
        CustomerResponse result = new CustomerResponse();
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(QuickBooksConfig.getCustomerEndpoint());
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setBody(JSON.serialize(payload, true));

            HttpResponse res  = new Http().send(req);
            result.statusCode = res.getStatusCode();

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                result.success               = true;
                Map<String, Object> body     = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> customer = (Map<String, Object>) body.get('Customer');
                result.qbCustomerId          = (String) customer.get('Id');
                result.syncToken             = (String) customer.get('SyncToken');
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