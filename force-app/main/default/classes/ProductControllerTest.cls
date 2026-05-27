@isTest
public class ProductControllerTest {

    static Pricebook2 pr;
    static Product2 pro;
    static PricebookEntry pre;
    static Group coordinatorQueue;

    @testSetup
    static void setupData() {
        coordinatorQueue = new Group(Name = 'Care Coordinator Prospect Queue', Type = 'Queue');
        insert coordinatorQueue;
        
        Product2 pro= New Product2();
        pro.Name='Test Product';
        pro.Description = 'Test Product Description';
        Insert pro;

        pr = new Pricebook2();
        pr.Name='Test Pricebook';
        pr.IsActive=True;
        Insert pr;

        String standardPricebook = Test.getStandardPricebookId();
        Pricebook2 prID2 = new Pricebook2(
    	Id = standardPricebook,
    	IsActive = true
		);
		update prID2;

        pre=New PricebookEntry();
        pre.Pricebook2Id=prID2.Id;
        pre.Product2Id=pro.Id;
        pre.UnitPrice=100;
        pre.isActive=true;
        Insert pre;

        // Create required Payment Method Set
        MerchantAccount merchant = new MerchantAccount(
    	Name = 'Test Merchant Account',
    	Status = 'Active',
        Mode = System.Label.Payment_Mode,
        CountryIsoCode = 'US'
		);
		insert merchant;
        MerchAccPaymentMethodSet pms = new MerchAccPaymentMethodSet(DeveloperName = 'BatonCare_PMS',MerchantAccountId = merchant.Id);
		insert pms;
        // Create Lead Record Type
        String leadMemberRecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Member').getRecordTypeId();

        // Create Person Account Record Type
        String memberRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Member').getRecordTypeId();
        
        System.runAs(new User(Id=UserInfo.getUserId())){
        QueuesObject testQueue = new QueueSObject(QueueID = coordinatorQueue.id, SObjectType = 'Task');
        insert testQueue;
        }
    }

    @isTest
    static void testGetProducts() {
        Test.startTest();
        List<Product2> products = ProductController.getProducts();
        Test.stopTest();
        System.assert(!products.isEmpty(), 'Product list should not be empty');
    }

    @isTest
    static void testGetProductPrices() {
        Test.startTest();
        Product2 prod = [Select ID,Name,Description FROM Product2 LIMIT 1];
        System.debug('Product'+ prod);
        List<PricebookEntry> entries = [
        SELECT Product2Id, UnitPrice,Pricebook2.IsStandard
        FROM PricebookEntry
        WHERE Product2Id =:prod.Id AND Pricebook2.IsStandard = TRUE AND IsActive = TRUE];
        System.debug('entries'+entries[0].Pricebook2.IsStandard);
        Map<Id, Decimal> prices = ProductController.getProductPrices(new List<Id>{ prod.Id });
        Test.stopTest();
        System.assertEquals(1, prices.size(), 'Should return one price');
    }

    @isTest
    static void testCreatePayment() {
        Test.startTest();
        Product2 prod = [Select ID,Name,Description FROM Product2 LIMIT 1];
        System.debug('Product'+ prod);
        List<PricebookEntry> entries = [
        SELECT Product2Id, UnitPrice,Pricebook2.IsStandard
        FROM PricebookEntry
        WHERE Product2Id =:prod.Id AND Pricebook2.IsStandard = TRUE AND IsActive = TRUE];
        System.debug('entries'+entries[0].Pricebook2.IsStandard);
        
        String paymentId = ProductController.createPayment(new List<Id>{ prod.Id }, 'Self Registration');
        Test.stopTest();
        System.assertNotEquals(null, paymentId, 'Payment ID should be returned');
    }

    @isTest
    static void testGetPayment() {
        // Create dummy PaymentLink
        Test.startTest();
        Product2 prod = [Select ID,Name,Description FROM Product2 LIMIT 1];
        System.debug('Product'+ prod);
        List<PricebookEntry> entries = [
        SELECT Product2Id, UnitPrice,Pricebook2.IsStandard
        FROM PricebookEntry
        WHERE Product2Id =:prod.Id AND Pricebook2.IsStandard = TRUE AND IsActive = TRUE];
        System.debug('entries'+entries[0].Pricebook2.IsStandard);
        
        String paymentId = ProductController.createPayment(new List<Id>{ prod.Id }, 'Self Registration');
        PaymentLink pl = [Select ID,PaymentUrl FROM PaymentLink];
        String url = ProductController.getPayment(pl.Id);
        Test.stopTest();
        System.assertNotEquals(null, url, 'Payment URL should not be null');
    }

    @isTest
    static void testCreateLeadAndTask() {
        
        
        Test.startTest();
        String leadId = ProductController.createLeadAndTask('John', 'Doe', 'john@example.com', '1234567890', '123 Main St');
        Test.stopTest();
        System.assertNotEquals(null, leadId, 'Lead ID should be returned');
    }

    @isTest
    static void testCreateMemberPersonAccount() {
        Test.startTest();
        Id accId = ProductController.createMemberPersonAccount(
            'Jane', 'Doe', 'jane@example.com', '9876543210',
            '1 Main', 'New York', 'NY', '10001', 'United States'
        );
        Test.stopTest();
        System.assertNotEquals(null, accId, 'Account ID should be returned');
    }

    @isTest
    static void testGetCountryStatePicklists() {
        Test.startTest();
        Map<String, List<ProductController.PicklistValueWrapper>> picklists = ProductController.getCountryStatePicklists();
        Test.stopTest();
        System.assert(picklists.containsKey('states'), 'Should return state picklist');
    }
}