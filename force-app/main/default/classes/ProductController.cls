public without sharing class ProductController {
    @AuraEnabled(cacheable=true)
    public static List<Product2> getProducts() {
        return [
            SELECT Id, Name, Description
            FROM Product2 ORDER BY Description
            LIMIT 100
        ];
    }
    @AuraEnabled
    public static Map<Id, Decimal> getProductPrices(List<Id> productIds) {
    Map<Id, Decimal> priceMap = new Map<Id, Decimal>();
    List<PricebookEntry> entries = [
        SELECT Product2Id, UnitPrice
        FROM PricebookEntry
        WHERE Product2Id IN :productIds AND Pricebook2.IsStandard = TRUE AND IsActive = TRUE
    ];
    for (PricebookEntry entry : entries) {
        priceMap.put(entry.Product2Id, entry.UnitPrice);
    }
    system.debug('priceMap'+priceMap);
    return priceMap;
}

@AuraEnabled
public static String createPayment(List<Id> productIds, String registrationType) {
    Decimal total = 0;

    // Get standard Pricebook2 Id
    Id standardPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;

    // Query PricebookEntry and related Product2
    List<PricebookEntry> entries = [
        SELECT Id, Product2Id, UnitPrice, Product2.Name, Product2.Description, Product2.Id
        FROM PricebookEntry
        WHERE Product2Id IN :productIds
        AND Pricebook2Id = :standardPricebookId
        AND IsActive = TRUE
    ];
	System.debug('Entries'+entries);
    if (entries.isEmpty()) {
        throw new AuraHandledException('No active pricebook entries found for the product.');
    }

    PricebookEntry entry = entries[0];
    Product2 product = entry.Product2;
    total = entry.UnitPrice;

    // Create Opportunity
    String oppName = product.Name + ' - ' + total + ' - ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss');
    Opportunity opp = new Opportunity(
        Name = oppName,
        StageName = 'New',
        CloseDate = System.today(),
        Pricebook2Id = standardPricebookId
    );
    insert opp;

    // Create OpportunityLineItem
    OpportunityLineItem oli = new OpportunityLineItem(
        OpportunityId = opp.Id,
        PricebookEntryId = entry.Id,
        Quantity = 1,
        UnitPrice = total,
        Product2Id = product.Id
    );
    insert oli;

    // Query MerchAccPaymentMethodSet
    MerchAccPaymentMethodSet pms = [
        SELECT Id
        FROM MerchAccPaymentMethodSet
        WHERE DeveloperName =: System.Label.Payment_Method_Name
        LIMIT 1
    ];

    // Create PaymentLink
    PaymentLink payment = new PaymentLink();
    payment.PaymentMethodSetId = pms.Id;
    payment.UsageType = 'SingleUse';
    payment.Amount = total;
    payment.Registration_Type__c = registrationType;
    payment.Title = product.Name;
    payment.Description = product.Description;
    payment.OpportunityId = opp.Id;

    insert payment;

    return payment.Id;
}


@AuraEnabled
public static String getPayment(Id paymentId) {
    System.debug('paymentId'+paymentId);
    PaymentLink pl = [Select Id, PaymentUrl FROM PaymentLink WHERE Id =: paymentId];
    return pl.PaymentUrl;
}

@AuraEnabled
public static String createLeadAndTask(String firstName, String lastName, String email, String phone, String shippingAddress) {
    // Find RecordTypeId for 'Member'
    
    String leadMemberRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Member').getRecordTypeId();

    // Create Lead
    Lead newLead = new Lead(
        FirstName = firstName,
        LastName = lastName,
        Email = email,
        Phone = phone,
        Street = shippingAddress, // maps to Lead.Address
        RecordTypeId = leadMemberRecordTypeId,
        Bypass_Duplicate_Rules__c = True,
        Status = 'New'
    );
    insert newLead;

    // Get Care Coordinator Queue Id
    Id careCoordinatorQueue = System.Label.Care_Coordinator_Queue ;
    // Create Task assigned to queue
    Task followupTask = new Task(
        WhoId = newLead.Id,
        OwnerId = careCoordinatorQueue,
        Subject = 'Follow up with new BatonCare prospect '+newLead.Name,
        Status = 'Not Started',
        Priority = 'Normal'
    );
    insert followupTask;

    return newLead.Id;
}

@AuraEnabled
public static Id createMemberPersonAccount(String firstName, String lastName, String email, String phone, 
                                           String street, String city, String state, String postalCode, String country) {
    // Get Person Account RecordTypeId for 'Member' (you can keep hardcoded ID if you prefer)
    
                                               
    String memberRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Member').getRecordTypeId();

    Account acc = new Account();
    acc.RecordTypeId = memberRecordTypeId; 
    acc.FirstName = firstName;
    acc.LastName = lastName;
    acc.PersonEmail = email;
    acc.PersonMobilePhone = phone;
    acc.BillingStreet = street;
    acc.BillingCity = city;
    acc.BillingStateCode = state;
    acc.BillingPostalCode = postalCode;
    acc.BillingCountry = country;
    acc.Bypass_Duplicate_Rules__c = True;
    
    insert acc;
    
    return acc.Id;
}
public class PicklistValueWrapper {
    @AuraEnabled public String label;
    @AuraEnabled public String value;

    public PicklistValueWrapper(Schema.PicklistEntry entry) {
        this.label = entry.getLabel();
        this.value = entry.getValue();
    }
}

@AuraEnabled(cacheable=true)
public static Map<String, List<PicklistValueWrapper>> getCountryStatePicklists() {
    Map<String, List<PicklistValueWrapper>> result = new Map<String, List<PicklistValueWrapper>>();

    // Get Country Picklist (from Account.ShippingCountryCode)
    /*List<PicklistValueWrapper> countryList = new List<PicklistValueWrapper>();
    Schema.DescribeFieldResult countryDescribe = Account.ShippingCountryCode.getDescribe();
    for (Schema.PicklistEntry entry : countryDescribe.getPicklistValues()) {
        system.debug('entry'+entry);
        countryList.add(new PicklistValueWrapper(entry));
    }
    result.put('countries', countryList);
    */
    // Get State Picklist (from Account.ShippingStateCode)
    List<PicklistValueWrapper> stateList = new List<PicklistValueWrapper>();
    Schema.DescribeFieldResult stateDescribe = Account.ShippingStateCode.getDescribe();
    for (Schema.PicklistEntry entry : stateDescribe.getPicklistValues()) {
        stateList.add(new PicklistValueWrapper(entry));
    }
    result.put('states', stateList);

    return result;
}




}