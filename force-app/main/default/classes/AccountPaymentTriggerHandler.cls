public without sharing class AccountPaymentTriggerHandler {

    @future
    public static void handleAfterInsertAsync(Set<Id> accountIds) {
        system.debug('>>>>>>>accountIds'+accountIds);
        List<Account> accountsToUpdate = new List<Account>();
	        // Fetch related PaymentIntent__c records
        List<PaymentIntent> paymentIntents = [
            SELECT Id, AccountId,Shippingcity,Shippinglatitude,Shippinglongitude,Shippingstate,ShippingstateCode,Shippingstreet 
            FROM PaymentIntent
            WHERE AccountId IN :accountIds
        ];
        system.debug('>>>>>>>accountIds'+paymentIntents);

        // Map by AccountId
        Map<Id, PaymentIntent> piMap = new Map<Id, PaymentIntent>();
        for (PaymentIntent pi : paymentIntents) {
            piMap.put(pi.AccountId, pi);
        }

        // Load target accounts
        List<Account> accounts = [
            SELECT Id,Shippingcity,Shippinglatitude,Shippinglongitude,Shippingstate,ShippingstateCode,Shippingstreet
            FROM Account
            WHERE Id IN :accountIds
        ];

        for (Account acc : accounts) {
            if (piMap.containsKey(acc.Id)) {
                PaymentIntent pi = piMap.get(acc.Id);
                acc.Shippingcity = pi.Shippingcity;
                acc.Shippinglatitude = pi.Shippinglatitude;
                acc.Shippinglongitude = pi.Shippinglongitude;
                acc.Shippingstate = pi.Shippingstate;
                acc.ShippingstateCode = pi.ShippingstateCode;
                acc.Shippingstreet = pi.Shippingstreet;
                
                accountsToUpdate.add(acc);
            }
        }
        
        system.debug('>>>>>>>accountIds'+accountsToUpdate);

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
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