public class QuickBooksConfig {
    
    public static final String NAMED_CREDENTIAL = 'callout:QuickBooks';
    public static final String API_VERSION      = '75';
    public static final String CUSTOMER_ENDPOINT = '/v3/company/{0}/customer?minorversion=' + API_VERSION;
    
    public static String getCompanyId() {
        QuickBook_Config__mdt config = QuickBook_Config__mdt.getInstance('Default');
        if (config == null) throw new QuickBooksException('QuickBooks Config metadata not found');
        return config.Company_Id__c;
    }
    
    public static String getCustomerEndpoint() {
        return NAMED_CREDENTIAL + String.format(CUSTOMER_ENDPOINT, new List<String>{ getCompanyId() });
    }
    
    public static String getDefaultIncomeAccountId() {
    QuickBook_Config__mdt config = QuickBook_Config__mdt.getInstance('Default');
    if (config == null || String.isBlank(config.Income_Account__c)) {
        throw new QuickBooksException('Default Income Account Id not configured');
    }
    return config.Income_Account__c;
}
    
    public class QuickBooksException extends Exception {}
}