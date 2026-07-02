@RestResource(urlMapping='/stripe/session/*')
global without sharing class StripeSessionResource {
    
    @HttpGet
    global static void getSessionIds() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        
        try {
            RestRequest req = RestContext.request;
            if (req == null || req.params == null) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'message' => 'Invalid request'
                }));
                return;
            }
            
            String sessionId = req.params.get('sessionId');
            if (String.isNotBlank(sessionId)) sessionId = sessionId.trim();
            
            if (String.isBlank(sessionId)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'message' => 'sessionId parameter is required'
                }));
                return;
            }
            
            List<Account> accounts = [
                SELECT Id, 
                       Biological_Sex_at_Birth__c,
                       FirstName, 
                       LastName, 
                       PersonEmail, 
                       PersonMobilePhone,
                       Date_of_Birth__pc,
                       Age__pc,
                       Stripe_Session_Id__c,
                       PersonMailingStreet,
                       PersonMailingCity,
                       PersonMailingState,
                       PersonMailingPostalCode,
                       PersonMailingCountry
                FROM Account
                WHERE Stripe_Session_Id__c = :sessionId
                LIMIT 1
            ];
            
            if (accounts.isEmpty()) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'success' => false,
                    'message' => 'No Account found for sessionId: ' + sessionId
                }));
                return;
            }
            
            Account acc = accounts[0];
            
            List<Opportunity> opps = [
                SELECT Id,
                       Name,
                       Amount,
                       AccountId,
                       CloseDate,
                       Maximum_Members_Allowed__c,
                       Renewal_Date__c,
                       Membership_fee_Paid__c,
                       Subscription_Id__c
                FROM Opportunity
                WHERE AccountId = :acc.Id
            ];

            Map<Id, List<Opportunity>> accOppMap = new Map<Id, List<Opportunity>>();
            for (Opportunity opp : opps) {
                if (!accOppMap.containsKey(opp.AccountId)) {
                    accOppMap.put(opp.AccountId, new List<Opportunity>());
                }
                accOppMap.get(opp.AccountId).add(opp);
            }
            
            Map<String, Object> primaryMember = new Map<String, Object>{
                'First Name'    => acc.FirstName                  != null ? acc.FirstName                         : '',
                'Last Name'     => acc.LastName                   != null ? acc.LastName                          : '',
                'Email'         => acc.PersonEmail                != null ? acc.PersonEmail                       : '',
                'Phone'         => acc.PersonMobilePhone          != null ? acc.PersonMobilePhone                 : '',
                'Gender'        => acc.Biological_Sex_at_Birth__c != null ? acc.Biological_Sex_at_Birth__c        : '',
                'Date of Birth' => acc.Date_of_Birth__pc          != null ? String.valueOf(acc.Date_of_Birth__pc) : '',
                'Age'           => acc.Age__pc                    != null ? acc.Age__pc                           : 0,
                'Street'        => acc.PersonMailingStreet        != null ? acc.PersonMailingStreet               : '',
                'City'          => acc.PersonMailingCity          != null ? acc.PersonMailingCity                 : '',
                'State'         => acc.PersonMailingState         != null ? acc.PersonMailingState                : '',
                'Zip'           => acc.PersonMailingPostalCode    != null ? acc.PersonMailingPostalCode           : '',
                'Country'       => acc.PersonMailingCountry       != null ? acc.PersonMailingCountry              : ''
            };
            
            List<Map<String, Object>> oppList = new List<Map<String, Object>>();
           for (Opportunity opp : (accOppMap.containsKey(acc.Id) ? accOppMap.get(acc.Id) : new List<Opportunity>())) {
               String planType = String.isNotBlank(opp.Name) && opp.Name.contains(' - ')
                   ? opp.Name.split(' - ')[0]
                   : opp.Name;

                Map<String, Object> oppMap = new Map<String, Object>{
                    'Plan Type'           => planType,
                    'Plan Amount'         => opp.Amount                 != null ? opp.Amount                          : 0,
                    'Coverage Start Date' => opp.CloseDate               != null ? String.valueOf(opp.CloseDate)       : '',
                    'Coverage End Date'   => opp.Renewal_Date__c         != null ? String.valueOf(opp.Renewal_Date__c) : '',
                    'Membership Fee Paid' => opp.Membership_fee_Paid__c  != null ? opp.Membership_fee_Paid__c          : 0,
                    'Billing Cycle'       => 'Annual'
                };

                if (planType == 'Family Plan') {
                    oppMap.put('is_unlimitedchildren', true);
                } else {
                    oppMap.put('Maximum Members Allowed', opp.Maximum_Members_Allowed__c != null ? opp.Maximum_Members_Allowed__c : '0');
                }
            
                oppList.add(oppMap);
            }
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success'        => true,
                'sessionId'      => acc.Stripe_Session_Id__c != null ? acc.Stripe_Session_Id__c : '',
                'accountId'      => acc.Id,
                'Primary Member' => primaryMember,
                'Selected Plans' => oppList
            }));
            
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success' => false,
                    'message' => e.getMessage()
            }));
        }
    }
}