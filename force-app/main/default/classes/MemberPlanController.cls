public without sharing class MemberPlanController {
    @AuraEnabled(cacheable=false)
    public static String sendAllMemberPlansToThirdParty(Id accountId){
        try{
            if(accountId == null){
                throw new AuraHandledException('Member id is Required');
            }
            
            List<MemberPlan> memberPlans = [
                SELECT Id, Name, MemberId, medicalcoverage__Payer_Name__c, MemberNumber,
                medicalcoverage__Group_Name__c, GroupNumber, EffectiveFrom,
                medicalcoverage__As_of_Date__c, medicalcoverage__Insurance_Type__c,
                medicalcoverage__Is_Government_Payer__c, RelationshipToSubscriber,
                VerificationStatus, medicalcoverage__Gender__c, CreatedDate
                FROM MemberPlan
                WHERE MemberId = :accountId
                ORDER BY CreatedDate DESC LIMIT 1000];
            if (memberPlans.isEmpty()) {
                throw new AuraHandledException('No Member Plan records found for this Account.');
            }
            Set<Id> memberPlanIds = new Map<Id, MemberPlan>(memberPlans).keySet();
            List<CoverageBenefit> coverageBenefits = [
                SELECT Id, Name, MemberId, MemberPlanId,medicalcoverage__InsuranceType__c,
                medicalcoverage__Individual_In_Network_Deductible_Total__c,
                medicalcoverage__Individual_Out_of_Network_Deductible_Tot__c,
                IndividualInNetworkDeductibleRemaining,
                IndividualOutofNetworkDeductibleRemain,
                medicalcoverage__Individual_In_Network_Deductible_Notes__c,
                medicalcoverage__Individual_OutofNetwork_Deductible_Note__c,
                medicalcoverage__Family_In_Network_Deductible_Total__c,
                medicalcoverage__Family_Out_of_Network_Deductible_Total__c,
                FamilyInNetworkDeductibleRemaining,
                FamilyOutofNetworkOutofPocketRemaining,
                medicalcoverage__Family_In_Network_Deductible_Notes__c,
                medicalcoverage__Family_Out_of_Network_Deductible_Notes__c,
                medicalcoverage__Individual_NAN_Deductible_Total__c,
                medicalcoverage__Family_NAN_Deductible_Total__c,
                medicalcoverage__Individual_NAN_Deductible_Remaining__c,
                medicalcoverage__Family_NAN_Deductible_Remaining__c,
                medicalcoverage__Individual_NAN_Deductible_Notes__c,
                medicalcoverage__Family_NAN_Deductible_Notes__c,
                InNetworkCoinsuranceAmount,
                OutofNetworkCoinsuranceAmount,
                InNetworkCoinsurancePercentage,
                OutofNetworkCoinsurancePercentage,
                medicalcoverage__Out_of_Network_Coinsurance_Notes__c,
                medicalcoverage__Individual_In_Network_Out_of_Pocket_Tot__c,
                medicalcoverage__Individual_Out_Network_Out_Pocket_Total__c,
                IndividualInNetworkOutofPocketRemaining,
                IndividualOutofNetworkOutofPocketRemain,
                medicalcoverage__Individual_In_Network_Out_of_Pocket_Note__c,
                medicalcoverage__Individual_Out_of_Network_Out_of_Pocket__c,
                medicalcoverage__Family_In_Network_Out_of_Pocket_Total__c,
                medicalcoverage__Family_Out_of_Network_Out_of_Pocket_Tot__c,
                FamilyInNetworkOutofPocketRemaining,FamilyOutofNetworkDeductibleRemaining,
                medicalcoverage__Family_In_Network_Out_of_Pocket_Notes__c,
                medicalcoverage__Family_Out_of_Network_Out_of_Pocket_Note__c,
                medicalcoverage__Individual_NAN_Out_of_Pocket_Total__c,
                medicalcoverage__Family_NAN_Out_of_Pocket_Total__c,
                medicalcoverage__IndividualNANOutofPocketRemaining__c,
                medicalcoverage__FamilyNANOutofPocketRemaining__c,
                medicalcoverage__Individual_NAN_Out_of_Pocket_Note__c,
                medicalcoverage__Family_NAN_Out_of_Pocket_Notes__c
                FROM CoverageBenefit
                WHERE MemberPlanId IN :memberPlanIds];
            
            Set<Id> coverageBenefitIds = new Map<Id, CoverageBenefit>(coverageBenefits).keySet();
            List<CoverageBenefitItem> coverageBenefitItems = coverageBenefitIds.isEmpty() 
                ? new List<CoverageBenefitItem>() 
                : [SELECT Id, Name, MemberId, CoverageBenefitId 
                   FROM CoverageBenefitItem 
                   WHERE CoverageBenefitId IN :coverageBenefitIds];
                       
                       Set<Id> coverageBenefitItemIds = new Map<Id, CoverageBenefitItem>(coverageBenefitItems).keySet();
            
            // Query Coverage Benefit Item Details
            List<medicalcoverage__CoverageBenefitItemDetail__c> coverageBenefitItemDetails = coverageBenefitItemIds.isEmpty() 
                ? new List<medicalcoverage__CoverageBenefitItemDetail__c>() 
                : [SELECT Id, Name,
                   medicalcoverage__Coverage_Benefit_Item__c,
                   medicalcoverage__Cateogy__c,
                   Display_Category_New__c,
                   medicalcoverage__Value__c,
                   medicalcoverage__remainingAmount__c,
                   medicalcoverage__PayerNotes__c
                   FROM medicalcoverage__CoverageBenefitItemDetail__c
                   WHERE medicalcoverage__Coverage_Benefit_Item__c IN :coverageBenefitItemIds];
                       
                       Map<Id, List<CoverageBenefit>> planToBenefitsMap = new Map<Id, List<CoverageBenefit>>();
            Map<Id, List<CoverageBenefitItem>> benefitToItemsMap = new Map<Id, List<CoverageBenefitItem>>();
            Map<Id, List<medicalcoverage__CoverageBenefitItemDetail__c>> itemToDetailsMap = new Map<Id, List<medicalcoverage__CoverageBenefitItemDetail__c>>();
            
            for(CoverageBenefit cb : coverageBenefits){
                if(!planToBenefitsMap.containsKey(cb.MemberPlanId)){
                    planToBenefitsMap.put(cb.MemberPlanId, new List<CoverageBenefit>());
                }
                planToBenefitsMap.get(cb.MemberPlanId).add(cb);
            }
            for(CoverageBenefitItem cbi : coverageBenefitItems){
                if(!benefitToItemsMap.containsKey(cbi.CoverageBenefitId)){
                    benefitToItemsMap.put(cbi.CoverageBenefitId, new List<CoverageBenefitItem>());
                }
                benefitToItemsMap.get(cbi.CoverageBenefitId).add(cbi);
            }
            for(medicalcoverage__CoverageBenefitItemDetail__c cbid : coverageBenefitItemDetails){
                if(!itemToDetailsMap.containsKey(cbid.medicalcoverage__Coverage_Benefit_Item__c)){
                    itemToDetailsMap.put(cbid.medicalcoverage__Coverage_Benefit_Item__c, new List<medicalcoverage__CoverageBenefitItemDetail__c>());
                }
                itemToDetailsMap.get(cbid.medicalcoverage__Coverage_Benefit_Item__c).add(cbid);
            }
            
            List<Map<String, Object>> plansList = new List<Map<String, Object>>();
            
            for(MemberPlan plan : memberPlans){
                List<Map<String, Object>> coverageBenefitsList = new List<Map<String, Object>>();
                List<CoverageBenefit> planBenefits = planToBenefitsMap.get(plan.Id);
                
                if(planBenefits != null){
                    for(CoverageBenefit cb : planBenefits){
                        List<Map<String, Object>> coverageBenefitItemsList = new List<Map<String, Object>>();
                        
                        // Get items for this benefit
                        List<CoverageBenefitItem> benefitItems = benefitToItemsMap.get(cb.Id);
                        
                        if(benefitItems != null){
                            for(CoverageBenefitItem cbi : benefitItems){
                                List<Map<String, Object>> coverageBenefitItemDetailsList = new List<Map<String, Object>>();
                                
                                // Get details for this item
                                List<medicalcoverage__CoverageBenefitItemDetail__c> itemDetails = itemToDetailsMap.get(cbi.Id);
                                
                                if(itemDetails != null){
                                    for(medicalcoverage__CoverageBenefitItemDetail__c cbid : itemDetails){
                                        coverageBenefitItemDetailsList.add(new Map<String, Object>{
                                            'CoverageBenefitItemDetailId' => cbid.Id,
                                                'Name' => cbid.Name,
                                                'CoverageBenefitItemId' => cbid.medicalcoverage__Coverage_Benefit_Item__c,
                                                'Category' => cbid.medicalcoverage__Cateogy__c,
                                                'DisplayCategory' => cbid.Display_Category_New__c,
                                                'TotalAmount' => cbid.medicalcoverage__Value__c,
                                                'RemainingAmount' => cbid.medicalcoverage__remainingAmount__c,
                                                'PayerNotes' => cbid.medicalcoverage__PayerNotes__c 
                                                });
                                    }
                                }
                                coverageBenefitItemsList.add(new Map<String, Object>{
                                    'CoverageBenefitItemId' => cbi.Id,
                                        'Name' => cbi.Name,
                                        'CoverageBenefitId' => cbi.CoverageBenefitId,
                                        'CoverageBenefitItemDetails' => coverageBenefitItemDetailsList
                                        });
                            }
                        }
                        
                        coverageBenefitsList.add(new Map<String, Object>{
                            'CoverageBenefitId' => cb.Id,
                                'Name' => cb.Name,
                                'MemberId' => cb.MemberId,
                                'MemberPlanId' => cb.MemberPlanId,
                                'Individual_In_Network_Deductible_Total' => cb.medicalcoverage__Individual_In_Network_Deductible_Total__c,
                                'Individual_In_Network_Deductible_Remaining' => cb.IndividualInNetworkDeductibleRemaining,
                                'Individual_In_Network_Deductible_Notes' => cb.medicalcoverage__Individual_In_Network_Deductible_Notes__c,
                                'Individual_Out_of_Network_Deductible_Total' => cb.medicalcoverage__Individual_Out_of_Network_Deductible_Tot__c,
                                'Individual_Out_of_Network_Deductible_Remaining' => cb.IndividualOutofNetworkDeductibleRemain,
                                'Individual_Out_of_Network_Deductible_Notes' => cb.medicalcoverage__Individual_OutofNetwork_Deductible_Note__c,
                                'Family_In_Network_Deductible_Total' => cb.medicalcoverage__Family_In_Network_Deductible_Total__c,
                                'Family_In_Network_Deductible_Remaining' => cb.FamilyInNetworkDeductibleRemaining,
                                'Family_In_Network_Deductible_Notes' => cb.medicalcoverage__Family_In_Network_Deductible_Notes__c,
                                
                                // ========== DEDUCTIBLE - FAMILY OUT-OF-NETWORK ==========
                                'Family_Out_of_Network_Deductible_Total' => cb.medicalcoverage__Family_Out_of_Network_Deductible_Total__c,
                                'Family_Out_of_Network_Deductible_Remaining' => cb.FamilyOutofNetworkDeductibleRemaining,
                                'Family_Out_of_Network_Deductible_Notes' => cb.medicalcoverage__Family_In_Network_Deductible_Notes__c,
                                
                                // ========== DEDUCTIBLE - INDIVIDUAL NAN ==========
                                'Individual_NAN_Deductible_Total' => cb.medicalcoverage__Individual_NAN_Deductible_Total__c,
                                'Individual_NAN_Deductible_Remaining' => cb.medicalcoverage__Individual_NAN_Deductible_Remaining__c,
                                'Individual_NAN_Deductible_Notes' => cb.medicalcoverage__Individual_NAN_Deductible_Notes__c,
                                
                                // ========== DEDUCTIBLE - FAMILY NAN ==========
                                'Family_NAN_Deductible_Total' => cb.medicalcoverage__Family_NAN_Deductible_Total__c,
                                'Family_NAN_Deductible_Remaining' => cb.medicalcoverage__Family_NAN_Deductible_Remaining__c,
                                'Family_NAN_Deductible_Notes' => cb.medicalcoverage__Family_NAN_Deductible_Notes__c,
                                
                                // ========== COINSURANCE ==========
                                'In_Network_Coinsurance_Amount' => cb.InNetworkCoinsuranceAmount,
                                'Out_of_Network_Coinsurance_Amount' => cb.OutofNetworkCoinsuranceAmount,
                                'In_Network_Coinsurance_Percentage' => cb.InNetworkCoinsurancePercentage,
                                'Out_of_Network_Coinsurance_Percentage' => cb.OutofNetworkCoinsurancePercentage,
                                'Out_of_Network_Coinsurance_Notes' => cb.medicalcoverage__Out_of_Network_Coinsurance_Notes__c,
                                
                                // ========== OUT-OF-POCKET - INDIVIDUAL IN-NETWORK ==========
                                'Individual_In_Network_Out_of_Pocket_Total' => cb.medicalcoverage__Individual_In_Network_Out_of_Pocket_Tot__c,
                                'Individual_In_Network_Out_of_Pocket_Remaining' => cb.IndividualInNetworkOutofPocketRemaining,
                                'Individual_In_Network_Out_of_Pocket_Notes' => cb.medicalcoverage__Individual_In_Network_Out_of_Pocket_Note__c,
                                
                                // ========== OUT-OF-POCKET - INDIVIDUAL OUT-OF-NETWORK ==========
                                'Individual_Out_of_Network_Out_of_Pocket_Total' => cb.medicalcoverage__Individual_Out_Network_Out_Pocket_Total__c,
                                'Individual_Out_of_Network_Out_of_Pocket_Remaining' => cb.IndividualOutofNetworkOutofPocketRemain,
                                'Individual_Out_of_Network_Out_of_Pocket_Notes' => cb.medicalcoverage__Individual_Out_of_Network_Out_of_Pocket__c,
                                
                                // ========== OUT-OF-POCKET - FAMILY IN-NETWORK ==========
                                'Family_In_Network_Out_of_Pocket_Total' => cb.medicalcoverage__Family_In_Network_Out_of_Pocket_Total__c,
                                'Family_In_Network_Out_of_Pocket_Remaining' => cb.FamilyInNetworkOutofPocketRemaining,
                                'Family_In_Network_Out_of_Pocket_Notes' => cb.medicalcoverage__Family_In_Network_Out_of_Pocket_Notes__c,
                                
                                // ========== OUT-OF-POCKET - FAMILY OUT-OF-NETWORK ==========
                                'Family_Out_of_Network_Out_of_Pocket_Total' => cb.medicalcoverage__Family_Out_of_Network_Out_of_Pocket_Tot__c,
                                'Family_Out_of_Network_Out_of_Pocket_Remaining' => cb.FamilyOutofNetworkOutofPocketRemaining,
                                'Family_Out_of_Network_Out_of_Pocket_Notes' => cb.medicalcoverage__Family_Out_of_Network_Out_of_Pocket_Note__c,
                                
                                // ========== OUT-OF-POCKET - INDIVIDUAL NAN ==========
                                'Individual_NAN_Out_of_Pocket_Total' => cb.medicalcoverage__Individual_NAN_Out_of_Pocket_Total__c,
                                'Individual_NAN_Out_of_Pocket_Remaining' => cb.medicalcoverage__IndividualNANOutofPocketRemaining__c,
                                'Individual_NAN_Out_of_Pocket_Notes' => cb.medicalcoverage__Individual_NAN_Out_of_Pocket_Note__c,
                                
                                // ========== OUT-OF-POCKET - FAMILY NAN ==========
                                'Family_NAN_Out_of_Pocket_Total' => cb.medicalcoverage__Family_NAN_Out_of_Pocket_Total__c,
                                'Family_NAN_Out_of_Pocket_Remaining' => cb.medicalcoverage__FamilyNANOutofPocketRemaining__c,
                                'Family_NAN_Out_of_Pocket_Notes' => cb.medicalcoverage__Family_NAN_Out_of_Pocket_Notes__c,
                                
                                'CoverageBenefitItems' => coverageBenefitItemsList
                                });
                    }
                }
                
                plansList.add(new Map<String, Object>{
                    'MemberPlanId' => plan.Id,
                        'Name' => plan.Name,
                        'MemberId' => plan.MemberId,
                        'PayerName' => plan.medicalcoverage__Payer_Name__c,
                        'MemberNumber' => plan.MemberNumber,
                        'GroupName' => plan.medicalcoverage__Group_Name__c,
                        'GroupNumber' => plan.GroupNumber,
                        'EffectiveFrom' => plan.EffectiveFrom,
                        'AsOfDate' => plan.medicalcoverage__As_of_Date__c,
                        'InsuranceType' => (planBenefits != null && !planBenefits.isEmpty()) ? planBenefits[0].medicalcoverage__InsuranceType__c : null,
                            'GovernmentPayer' => plan.medicalcoverage__Is_Government_Payer__c,
                            'RelationshipToSubscriber' => plan.RelationshipToSubscriber,
                            'Status' => plan.VerificationStatus,
                            'Gender' => plan.medicalcoverage__Gender__c,
                            'CreatedDate' => plan.CreatedDate,
                            'CoverageBenefits' => coverageBenefitsList
                            });
            }
            
            Map<String, Object> finalPayload = new Map<String, Object>{
                'Member_Plan' => plansList
                    };
                        
            String jsonBody = JSON.serializePretty(finalPayload);
            system.debug('payload>>>'+jsonBody);
            
            BatonPortalAPI__c settings = BatonPortalAPI__c.getOrgDefaults();
            if (settings == null || String.isBlank(settings.Insurance_Key__c)) {
                throw new AuraHandledException('BatonPortalAPI Insurance_Key__c not found');
            }
            
            String insuranceKey = settings.Insurance_Key__c;
            // MAKE CALLOUT
            HttpRequest req = new HttpRequest();
            req.setEndpoint(insuranceKey);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setBody(jsonBody);
            req.setTimeout(120000);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if(res.getStatusCode() >= 200 && res.getStatusCode() < 300){
                return 'Success: Sent ' + memberPlans.size() + ' Member Plan(s) successfully.';
            } else {
                throw new AuraHandledException('API Error: Status ' + res.getStatusCode() + ' - ' + res.getBody());
            }
            
       } catch (AuraHandledException  ex){
             throw ex;
        }
    }
}