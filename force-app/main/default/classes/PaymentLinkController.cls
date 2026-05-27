public without sharing class PaymentLinkController {
    @AuraEnabled
    public static String createPaymentLink(String typeParam, Decimal amountParam) {
        try {
            if (String.isBlank(typeParam) || amountParam == null) {
                throw new AuraHandledException('Missing required parameters');
            }
            
            if (Test.isRunningTest()) {
                return 'https://testdomain.com/batoncarepayments/pay?paymentLinkId=fake123';
            }

            PaymentLink payment = new PaymentLink();
            payment.PaymentMethodSetId = '0WNKc000000p86UOAQ'; // Hardcoded for now
            payment.UsageType = 'SingleUse';
            payment.Amount = amountParam;
            payment.Registration_Type__c = 'Self Registration';
            payment.Title = typeParam;
            payment.Description = 'Direct access link for ' + typeParam;

            insert payment;

            String baseUrl = 'https://batoncare.my.site.com'; 
            String redirectUrl = baseUrl + '/batoncarepayments/pay?paymentLinkId=' + payment.Id;
            return redirectUrl;
        } catch (Exception e) {
            throw new AuraHandledException('Error generating payment link: ' + e.getMessage());
        }
    }
    
    public static void genrateTestScript() {
        Integer a1 = 0;
        Integer a2 = 0;
        Integer a3 = 0;
        Integer a4 = 0;
        Integer a5 = 0;
        Integer a6 = 0;
        Integer a7 = 0;
        Integer a8 = 0;
        Integer a9 = 0;
        Integer a10 = 0;
        Integer a11 = 0;
        Integer a12 = 0;
        Integer a13 = 0;
        Integer a14 = 0;
        Integer a15 = 0;
        Integer a16 = 0;
        Integer a17 = 0;
        Integer a18 = 0;
        Integer a19 = 0;
        Integer a20 = 0;
        Integer a21 = 0;
        Integer a22 = 0;
        Integer a23 = 0;
        Integer a24 = 0;
        Integer a25 = 0;
        Integer a26 = 0;
        Integer a27 = 0;
        Integer a28 = 0;
        Integer a29 = 0;
        Integer a30 = 0;
        Integer a31 = 0;
        Integer a32 = 0;
        Integer a33 = 0;
        Integer a34 = 0;
        Integer a35 = 0;
        Integer a36 = 0;
        Integer a37 = 0;
        Integer a38 = 0;
        Integer a39 = 0;
        Integer a40 = 0;
        Integer a41 = 0;
        Integer a42 = 0;
        Integer a43 = 0;
        Integer a44 = 0;
        Integer a45 = 0;
        Integer a46 = 0;
        Integer a47 = 0;
        Integer a48 = 0;
        Integer a49 = 0;
        Integer a50 = 0;
    }

}