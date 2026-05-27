public class StripePaymentHandler {
    
    public class Result {
        public Boolean success;
        public String message;
        
        public Result() {}
        
        public Result(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }
    
   // Helper method to get automated user - testable
    @TestVisible
    private static User getAutomatedUser() {
        User automatedUser = null;
        
        if (Test.isRunningTest()) {
            // In test context, return any active admin user
            List<User> users = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 1];
            if (!users.isEmpty()) {
                automatedUser = users[0];
            }
        } else {
            // In production, use your specific user
            List<User> users = [SELECT Id FROM User WHERE Username = 'autoproc@00dkc000000j2romac' AND IsActive = true LIMIT 1];
            if (!users.isEmpty()) {
                automatedUser = users[0];
            }
        }
        if (automatedUser == null) {
            System.debug('No automated user found.');
        }
        
        return automatedUser;
    }

    public static Result processChargeSucceeded(Map<String, Object> charge) {
        try {
            Boolean paid = (Boolean) charge.get('paid');
            String status = (String) charge.get('status');
            
            if (paid != true || status != 'succeeded') {
                return new Result(false, 'Charge not successful.');
            }

            String paymentIntentId = (String) charge.get('payment_intent');
            String chargeId = (String) charge.get('id');
            
            System.debug('Extracted Payment Intent ID: ' + paymentIntentId);
            System.debug('Extracted Charge ID: ' + chargeId);
            
            Decimal amount = null;
            if (charge.containsKey('amount')) {
                amount = Decimal.valueOf(charge.get('amount').toString()) / 100;
            }
            
            String stripeCustomerId = (String) charge.get('customer');
            String stripeAccountId = null;
            String planName = null;
            
            if (charge.containsKey('metadata') && charge.get('metadata') != null) {
                Map<String, Object> metadata = (Map<String, Object>) charge.get('metadata');
                if (metadata.containsKey('Plan_Name')) {
                    planName = (String) metadata.get('Plan_Name');
                }
            }
            
            String email = null;
            String firstName = 'Unknown';
            String lastName = 'Unknown';
            Map<String, Object> addressMap = null;
            
            if (charge.containsKey('billing_details')) {
                Map<String, Object> billingDetails = (Map<String, Object>) charge.get('billing_details');
                email = (String) billingDetails.get('email');
                addressMap = (Map<String, Object>) billingDetails.get('address');
                
                String fullName = (String) billingDetails.get('name');
                if (!String.isBlank(fullName)) {
                    List<String> nameParts = fullName.split(' ');
                    if (nameParts.size() == 1) {
                        firstName = '';
                        lastName = nameParts[0];
                    } else if (nameParts.size() >= 2) {
                        firstName = nameParts[0];
                        lastName = '';
                        for (Integer i = 1; i < nameParts.size(); i++) {
                            if (i > 1) lastName += ' ';
                            lastName += nameParts[i];
                        }
                    }
                }
            }
            
            String paymentMode = null;
            if (charge.containsKey('metadata') && charge.get('metadata') != null) {
                Map<String, Object> metadata = (Map<String, Object>) charge.get('metadata');
                if (metadata.containsKey('mode')) {
                    paymentMode = (String) metadata.get('mode');
                }
            }
            
            // Use the helper method instead of direct query
            User automatedUser = getAutomatedUser(); 
            //Check if Person Account already exists by Customer ID
            Account account = null;
            if (!String.isBlank(stripeCustomerId)) {
                String customerUrl = 'https://dashboard.stripe.com/customers/' + stripeCustomerId;
                List<Account> existingStripeAccount = [
                    SELECT Id, FirstName, LastName, Email__c,PersonEmail, Stripe_Account_Id__c, 
                    Invoice_Id__c, Customer_Id__c, RecordType.DeveloperName
                    FROM Account
                    WHERE Customer_Id__c != null 
                    AND Customer_Id__c = :customerUrl 
                    AND RecordType.DeveloperName = 'PersonAccount'
                    ORDER BY CreatedDate DESC 
                    LIMIT 1
                ];
                
                if (!existingStripeAccount.isEmpty()) {
                    System.debug('Found existing Person Account by Customer ID: ' + stripeCustomerId);
                    account = existingStripeAccount[0];
                    
                    // Build payment link
                    String paymentLinkUrl = null;
                    if (!String.isBlank(paymentIntentId) && !String.isBlank(account.Stripe_Account_Id__c)) {
                        paymentLinkUrl = 'https://dashboard.stripe.com/' + account.Stripe_Account_Id__c + '/payments/' + paymentIntentId;
                    } 
                    // Create Stripe Transaction record for existing account
                    Stripe_Transaction__c txn = new Stripe_Transaction__c();
                    txn.Amount__c = amount;
                    txn.Email__c = email;
                    txn.Account__c = account.Id;
                    txn.OwnerId = automatedUser.Id;
                    if (status == 'succeeded') {
                        txn.Payment_Status__c = 'paid';
                    }
                    txn.Mode__c = 'subscription';
                    txn.Payment_Link__c = paymentLinkUrl;
                    txn.Payment_ID__c = paymentIntentId;

                    insert txn;  
                    return new Result(true, 'Stripe Transaction created for existing Person Account.');
                }
            }
            
            // Verify Person Account Record Type exists before creating new account
            Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
            if (!rtMap.containsKey('PersonAccount')) {
                throw new AuraHandledException('PersonAccount Record Type not available. Account creation blocked.');
            }
            
            Id personAccountRecordTypeId = rtMap.get('PersonAccount').getRecordTypeId();
            account = new Account();
            account.FirstName = firstName;
            account.LastName = lastName;
            account.PersonEmail = email;
            account.OwnerId = automatedUser.Id;
            account.RecordTypeId = personAccountRecordTypeId; 
            if (!String.isBlank(stripeCustomerId)) {
                account.Customer_Id__c = 'https://dashboard.stripe.com/customers/' + stripeCustomerId;
            }
            
            if (addressMap != null) {
                account.PersonMailingStreet = (String) addressMap.get('line1');
                account.PersonMailingCity= (String) addressMap.get('city');
                
                String stripeStateCode = (String) addressMap.get('state');
                String stripeCountryCode = (String) addressMap.get('country');
                
                account.PersonMailingCountry = convertCountryCodeToName(stripeCountryCode);
                account.PersonMailingState = convertStateCodeToName(stripeStateCode, stripeCountryCode);
                account.PersonMailingPostalCode = (String) addressMap.get('postal_code');
            }
            
            insert account;

            if (account != null && account.Id != null) {
                Map<String, Schema.RecordTypeInfo> oppRtMap = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
                if (!oppRtMap.containsKey('Patient_Referral')) {
                    System.debug('WARNING: Patient_Referral Record Type not found for Opportunity.');
                    return new Result(false, 'Patient_Referral Record Type not available for Opportunity.');
                }
                
                Id oppRecordTypeId = oppRtMap.get('Patient_Referral').getRecordTypeId();

                Opportunity opp = new Opportunity();
                opp.Name = planName + ' - Referral';
                opp.AccountId = account.Id;
                opp.StageName = 'Closed Won';
                opp.CloseDate = system.today();
                opp.Amount = amount;
                opp.Membership_fee_paid__c = amount;
                opp.OwnerId = automatedUser.Id;
                opp.RecordTypeId = oppRecordTypeId;
                
                insert opp;
                
                Stripe_Transaction__c txn = new Stripe_Transaction__c();
                txn.Amount__c = amount;
                txn.Email__c = email;
                txn.Account__c = account.Id;
                txn.Opportunity__c = opp.Id;
                txn.OwnerId = automatedUser.Id;
                txn.Payment_ID__c = paymentIntentId;
                
                insert txn;
            }
            
            return new Result(true, 'Person Account, Opportunity, and Stripe Transaction created successfully.');
            
        } catch (Exception e) {
            System.debug('Error processing charge.succeeded: ' + e.getMessage());
            return new Result(false, 'Error: ' + e.getMessage());
        }
    }
    
    public static Result getSubscriptionIdFromEvent(Object eventObj) {
        Integer maxAttempts = 5;
        Integer waitTimeMs = 2000; 
        Map<String, Object> eventObject;

        if (eventObj instanceof String) {
            try {
                eventObject = (Map<String, Object>) JSON.deserializeUntyped((String) eventObj);
            } catch (Exception ex) {
                return new Result(false, 'Failed to deserialize event JSON: ' + ex.getMessage());
            }
        } else if (eventObj instanceof Map<String, Object>) {
            eventObject = (Map<String, Object>) eventObj;
        } else {
            return new Result(false, 'Invalid event object type.');
        }

        try {
            Map<String, Object> dataObject;
            if (eventObject.containsKey('data') && eventObject.get('data') != null) {
                Map<String, Object> dataMap = (Map<String, Object>) eventObject.get('data');
                dataObject = (Map<String, Object>) dataMap.get('object');
            } else {
                dataObject = eventObject;
            }

            Map<String, Object> linesMap = (Map<String, Object>) dataObject.get('lines');
            List<Object> dataLines = (List<Object>) linesMap.get('data');
            Map<String, Object> firstLine = (Map<String, Object>) dataLines[0];
            Map<String, Object> parentMap = (Map<String, Object>) firstLine.get('parent');
            Map<String, Object> subscriptionItemDetails = (Map<String, Object>) parentMap.get('subscription_item_details');
            String subscriptionId = (String) subscriptionItemDetails.get('subscription');

            // Retry loop to find Opportunity
            List<Opportunity> opportunities = new List<Opportunity>();
            for (Integer attempt = 1; attempt <= maxAttempts; attempt++) {
                opportunities = [
                    SELECT Id, AccountId 
                    FROM Opportunity 
                    WHERE AccountId != null AND Subscription_Id__c != null 
                    AND Subscription_Id__c = :subscriptionId 
                    LIMIT 1
                ];

                if (!opportunities.isEmpty()) {
                    break;
                }

                if (attempt < maxAttempts && !Test.isRunningTest()) {
                    System.debug('No Opportunity found, retrying in ' + waitTimeMs + 'ms...');
                    Long startTime = System.now().getTime();
                    while (System.now().getTime() - startTime < waitTimeMs) {
                    
                    }
                }
            }

            if (opportunities.isEmpty()) {
                return new Result(false, 'No Opportunity found with Subscription ID: ' + subscriptionId);
            }

            List<Stripe_Transaction__c> stripeTransactions = [
                SELECT Id 
                FROM Stripe_Transaction__c 
                WHERE Account__c = :opportunities[0].AccountId 
                AND Opportunity__c = null
                LIMIT 1
            ];

            if (stripeTransactions.isEmpty()) {
                return new Result(true, 'No Stripe Transaction found — skipping update.');
            }
            stripeTransactions[0].Opportunity__c = opportunities[0].Id;
            update stripeTransactions[0];

            return new Result(true, 'Successfully updated Stripe Transaction');

        } catch (Exception ex) {
            return new Result(false, 'Error: ' + ex.getMessage());
        }
    }

    public static Result processInvoicePaymentWithRetry(Map<String, Object> session) {
        Result res = new Result();
        Integer maxAttempts = 5;
        Integer waitTimeMs = 2000; 
        
        try {
            String customerId = (String) session.get('customer');
            String invoiceId = (String) session.get('invoice');
            String subscriptionId = (String) session.get('subscription');
            String paymentMode = (String) session.get('mode');
            String paymentStatus = (String) session.get('payment_status');
            
            // Extract metadata
            String planName = null;
            String stripeAccountId = null;
            if (session.containsKey('metadata') && session.get('metadata') != null) {
                Map<String, Object> metadata = (Map<String, Object>) session.get('metadata');
                planName = (String) metadata.get('Plan_Name');
                stripeAccountId = (String) metadata.get('Stripe_account_id');
            }
            
            // Extract customer details for opportunity name
            String firstName = '';
            String phone = null;
            if (session.containsKey('customer_details')) {
                Map<String, Object> customerDetails = (Map<String, Object>) session.get('customer_details');
                String fullName = (String) customerDetails.get('name');
                if (!String.isBlank(fullName)) {
                    List<String> nameParts = fullName.split(' ');
                    if (nameParts.size() >= 1) {
                        firstName = nameParts[0];
                    }
                }
                phone = (String) customerDetails.get('phone');
            }
            
            if (String.isBlank(customerId)) {
                res.success = false;
                res.message = 'Missing Customer ID in session object';
                return res;
            }
            
            String customerUrl = 'https://dashboard.stripe.com/customers/' + customerId;
            Account account = null;
            for (Integer attempt = 1; attempt <= maxAttempts; attempt++) {
                System.debug('Attempt ' + attempt + ' of ' + maxAttempts + ' to find Account');
                
                // Try finding by Customer ID
                List<Account> accounts = [
                    SELECT Id, Invoice_Id__c, Phone,PersonMobilePhone, Stripe_Account_Id__c
                    FROM Account
                    WHERE Customer_Id__c = :customerUrl
                    AND RecordType.DeveloperName = 'PersonAccount'
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                
                if (!accounts.isEmpty()) {
                    account = accounts[0];
                    System.debug('Account found by Customer ID on attempt ' + attempt);
                    break;
                }
                
                // Wait before next attempt (except on last attempt)
                if (attempt < maxAttempts && !Test.isRunningTest()) {
                    System.debug('Account not found, waiting before retry...');
                    Long startTime = System.now().getTime();
                    while (System.now().getTime() - startTime < waitTimeMs) {
                        
                    }
                }
            }
            
            if (account == null) {
                res.success = false;
                res.message = 'No matching Account found for customer after ' + maxAttempts + ' attempts: ' + customerId;
                return res;
            }
            
            // Update Account Invoice_Id__c and Phone if available
            Boolean accountNeedsUpdate = false;
            if (!String.isBlank(invoiceId)) {
                account.Invoice_Id__c = invoiceId;
                accountNeedsUpdate = true;
            }
            if (!String.isBlank(phone) && String.isBlank(account.PersonMobilePhone)) {
                account.PersonMobilePhone = phone;
                accountNeedsUpdate = true;
            }
            if (!String.isBlank(stripeAccountId) && String.isBlank(account.Stripe_Account_Id__c)) {
                account.Stripe_Account_Id__c = stripeAccountId;
                accountNeedsUpdate = true;
            }
            
            if (accountNeedsUpdate) {
                update account;
            }
            
            // Query Opportunity linked to this Account
            List<Opportunity> existingOpps = [
                SELECT Id, Name, Subscription_Id__c
                FROM Opportunity
                WHERE AccountId = :account.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            // Update existing Opportunity name with Plan Name and Subscription ID if found
            if (!existingOpps.isEmpty()) {
                Opportunity opp = existingOpps[0];
                
                if (!String.isBlank(planName)) {
                    String existingName = opp.Name;
                    List<String> nameParts = existingName.split(' - ');
                    if (nameParts.size() > 1) {
                        opp.Name = planName;
                    } else {
                        opp.Name = planName;
                    }
                }
                
                if (!String.isBlank(subscriptionId) && String.isBlank(opp.Subscription_id__c)) {
                    opp.Subscription_Id__c = subscriptionId;
                }
                
                update opp;
            }
            
            // Query the latest Stripe_Transaction__c record linked to this Account
            List<Stripe_Transaction__c> txns = [
                SELECT Id, Payment_ID__c, Mode__c, Payment_Link__c, Payment_Status__c
                FROM Stripe_Transaction__c
                WHERE Account__c = :account.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            if (!txns.isEmpty()) {
                Stripe_Transaction__c txn = txns[0];
                Boolean txnNeedsUpdate = false;
                
                if (!String.isBlank(paymentMode) && String.isBlank(txn.Mode__c)) {
                    txn.Mode__c = paymentMode;
                    txnNeedsUpdate = true;
                }
                
                if (!String.isBlank(paymentStatus) && String.isBlank(txn.Payment_Status__c)) {
                    txn.Payment_Status__c = paymentStatus;
                    txnNeedsUpdate = true;
                }
                
                if (String.isBlank(txn.Payment_Link__c) && !String.isBlank(txn.Payment_ID__c) && !String.isBlank(stripeAccountId)) {
                    txn.Payment_Link__c = 'https://dashboard.stripe.com/' + stripeAccountId + '/payments/' + txn.Payment_ID__c;
                    txnNeedsUpdate = true;
                }
                
                if (txnNeedsUpdate) {
                    update txn;
                }
            }
            
            res.success = true;
            res.message = 'Successfully updated records for customer ' + customerId;
            
        } catch (Exception e) {
            res.success = false;
            res.message = 'Error processing checkout.session.completed: ' + e.getMessage();
        }
        
        return res;
    }
    
    private static String convertCountryCodeToName(String isoCode) {
        if (String.isBlank(isoCode)) return null;
        try {
            Schema.DescribeFieldResult fieldResult = Account.ShippingCountryCode.getDescribe();
            List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();
            for (Schema.PicklistEntry entry : entries) {
                if (entry.getValue().equalsIgnoreCase(isoCode)) {
                    return entry.getLabel();
                }
            }
        } catch (Exception e) {
            System.debug('Error converting country code: ' + e.getMessage());
        }
        return isoCode;
    }
    
    private static String convertStateCodeToName(String stateCode, String countryCode) {
        if (String.isBlank(stateCode)) return null;
        try {
            Schema.DescribeFieldResult fieldResult = Account.ShippingStateCode.getDescribe();
            List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();
            for (Schema.PicklistEntry entry : entries) {
                if (entry.getValue().equalsIgnoreCase(stateCode)) {
                    return entry.getLabel();
                }
            }
        } catch (Exception e) {
            System.debug('Error converting state code: ' + e.getMessage());
        }
        return stateCode;
    }
}