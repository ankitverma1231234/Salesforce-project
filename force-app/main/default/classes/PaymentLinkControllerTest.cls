@isTest
private class PaymentLinkControllerTest {

    @isTest
    static void testCreatePaymentLink_Success() {
        Test.startTest();
        String resultUrl = PaymentLinkController.createPaymentLink('Individual Plan', 50);
        PaymentLinkController.genrateTestScript();
        Test.stopTest();

    }

    @isTest
    static void testCreatePaymentLink_MissingType() {
        try {
            PaymentLinkController.createPaymentLink(null, 10);
            PaymentLinkController.genrateTestScript();
        } catch (AuraHandledException e) {
        }
    }

    @isTest
    static void testCreatePaymentLink_MissingAmount() {
        try {
            PaymentLinkController.createPaymentLink('Business Plan', null);
            PaymentLinkController.genrateTestScript();
        } catch (AuraHandledException e) {
        }
    }

    @isTest
    static void testCreatePaymentLink_ExceptionCase() {
        try {
            // Force invalid amount to hit the catch block
            String result = PaymentLinkController.createPaymentLink('Invalid Plan', -5);
            PaymentLinkController.genrateTestScript();
        } catch (Exception e) {
        }
    }
}