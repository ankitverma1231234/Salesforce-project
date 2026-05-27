public without sharing class MemberPlanCalloutFuture {

    @future(callout=true)
    public static void sendForCoverageBenefits(List<Id> coverageBenefitIds) {
        if (coverageBenefitIds.isEmpty()) return;

        Set<Id> cbIds = new Set<Id>(coverageBenefitIds);
        Set<Id> memberPlanIds = new Set<Id>();

        for (CoverageBenefit cb : [
                SELECT MemberPlanId
                FROM   CoverageBenefit
                WHERE  Id IN :cbIds
                AND  MemberPlanId != null]) {
            memberPlanIds.add(cb.MemberPlanId);
        }
        sendPayload(memberPlanIds, cbIds);
    }


    @future(callout=true)
    public static void sendForCoverageBenefitItems(List<Id> coverageBenefitItemIds) {
        if (coverageBenefitItemIds.isEmpty()) return;

        Set<Id> memberPlanIds      = new Set<Id>();
        Set<Id> coverageBenefitIds = new Set<Id>();

        for (CoverageBenefitItem cbi : [
                SELECT CoverageBenefitId, CoverageBenefit.MemberPlanId
                FROM   CoverageBenefitItem
                WHERE  Id IN :coverageBenefitItemIds]) {
            if (cbi.CoverageBenefit != null
                    && cbi.CoverageBenefit.MemberPlanId != null) {
                memberPlanIds.add(cbi.CoverageBenefit.MemberPlanId);
                coverageBenefitIds.add(cbi.CoverageBenefitId); 
            }
        }
        sendPayload(memberPlanIds, coverageBenefitIds);
    }

 
    @future(callout=true)
    public static void sendForCoverageBenefitItemDetails(List<Id> detailIds) {
        if (detailIds.isEmpty()) return;

        Set<Id> coverageBenefitItemIds = new Set<Id>();
        for (medicalcoverage__CoverageBenefitItemDetail__c cbid : [
                SELECT medicalcoverage__Coverage_Benefit_Item__c
                FROM   medicalcoverage__CoverageBenefitItemDetail__c
                WHERE  Id IN :detailIds
                AND    medicalcoverage__Coverage_Benefit_Item__c != null]) {
            coverageBenefitItemIds.add(cbid.medicalcoverage__Coverage_Benefit_Item__c);
        }

        if (coverageBenefitItemIds.isEmpty()) return;

        Set<Id> memberPlanIds      = new Set<Id>();
        Set<Id> coverageBenefitIds = new Set<Id>();
        for (CoverageBenefitItem cbi : [
                SELECT CoverageBenefitId, CoverageBenefit.MemberPlanId
                FROM   CoverageBenefitItem
                WHERE  Id IN :coverageBenefitItemIds]) {
            if (cbi.CoverageBenefit != null
                    && cbi.CoverageBenefit.MemberPlanId != null) {
                memberPlanIds.add(cbi.CoverageBenefit.MemberPlanId);
                coverageBenefitIds.add(cbi.CoverageBenefitId); 
            }
        }

        sendPayload(memberPlanIds, coverageBenefitIds);
    }

   
    private static void sendPayload(Set<Id> memberPlanIds,
                                    Set<Id> filterCoverageBenefitIds) {
        if (memberPlanIds.isEmpty()) return;

        try {
            // ── 1. MemberPlans ────────────────────────────────────────────────
            List<MemberPlan> memberPlans = [
                SELECT  Id, Name, MemberId,
                        medicalcoverage__Payer_Name__c, MemberNumber,
                        medicalcoverage__Group_Name__c, GroupNumber,
                        EffectiveFrom, medicalcoverage__As_of_Date__c,
                        medicalcoverage__Insurance_Type__c,
                        medicalcoverage__Is_Government_Payer__c,
                        RelationshipToSubscriber, VerificationStatus,
                        medicalcoverage__Gender__c, CreatedDate
                        FROM    MemberPlan
                        WHERE   Id IN :memberPlanIds];

            if (memberPlans.isEmpty()) return;

            // ── 2. ONLY the specific CoverageBenefits (filtered) ──────────────
            List<CoverageBenefit> coverageBenefits = [
                SELECT  Id, Name, MemberId, MemberPlanId,
                        medicalcoverage__InsuranceType__c,
                        medicalcoverage__Individual_In_Network_Deductible_Total__c,
                        IndividualInNetworkDeductibleRemaining,
                        medicalcoverage__Individual_In_Network_Deductible_Notes__c,
                        medicalcoverage__Individual_Out_of_Network_Deductible_Tot__c,
                        IndividualOutofNetworkDeductibleRemain,
                        medicalcoverage__Individual_OutofNetwork_Deductible_Note__c,
                        medicalcoverage__Family_In_Network_Deductible_Total__c,
                        FamilyInNetworkDeductibleRemaining,
                        medicalcoverage__Family_In_Network_Deductible_Notes__c,
                        medicalcoverage__Family_Out_of_Network_Deductible_Total__c,
                        FamilyOutofNetworkDeductibleRemaining,
                        medicalcoverage__Family_Out_of_Network_Deductible_Notes__c,
                        medicalcoverage__Individual_NAN_Deductible_Total__c,
                        medicalcoverage__Individual_NAN_Deductible_Remaining__c,
                        medicalcoverage__Individual_NAN_Deductible_Notes__c,
                        medicalcoverage__Family_NAN_Deductible_Total__c,
                        medicalcoverage__Family_NAN_Deductible_Remaining__c,
                        medicalcoverage__Family_NAN_Deductible_Notes__c,
                        InNetworkCoinsuranceAmount,
                        OutofNetworkCoinsuranceAmount,
                        InNetworkCoinsurancePercentage,
                        OutofNetworkCoinsurancePercentage,
                        medicalcoverage__Out_of_Network_Coinsurance_Notes__c,
                        medicalcoverage__Individual_In_Network_Out_of_Pocket_Tot__c,
                        IndividualInNetworkOutofPocketRemaining,
                        medicalcoverage__Individual_In_Network_Out_of_Pocket_Note__c,
                        medicalcoverage__Individual_Out_Network_Out_Pocket_Total__c,
                        IndividualOutofNetworkOutofPocketRemain,
                        medicalcoverage__Individual_Out_of_Network_Out_of_Pocket__c,
                        medicalcoverage__Family_In_Network_Out_of_Pocket_Total__c,
                        FamilyInNetworkOutofPocketRemaining,
                        medicalcoverage__Family_In_Network_Out_of_Pocket_Notes__c,
                        medicalcoverage__Family_Out_of_Network_Out_of_Pocket_Tot__c,
                        FamilyOutofNetworkOutofPocketRemaining,
                        medicalcoverage__Family_Out_of_Network_Out_of_Pocket_Note__c,
                        medicalcoverage__Individual_NAN_Out_of_Pocket_Total__c,
                        medicalcoverage__IndividualNANOutofPocketRemaining__c,
                        medicalcoverage__Individual_NAN_Out_of_Pocket_Note__c,
                        medicalcoverage__Family_NAN_Out_of_Pocket_Total__c,
                        medicalcoverage__FamilyNANOutofPocketRemaining__c,
                        medicalcoverage__Family_NAN_Out_of_Pocket_Notes__c
                        FROM    CoverageBenefit
                        WHERE   MemberPlanId IN :memberPlanIds
                        AND     Id IN :filterCoverageBenefitIds]; 

            Set<Id> coverageBenefitIds = new Map<Id, CoverageBenefit>(coverageBenefits).keySet();

            // ── 3. ALL CoverageBenefitItems for those specific CBs ────────────
            List<CoverageBenefitItem> coverageBenefitItems =
                coverageBenefitIds.isEmpty()
                ? new List<CoverageBenefitItem>()
                : [SELECT Id, Name, MemberId, CoverageBenefitId
                   FROM   CoverageBenefitItem
                   WHERE  CoverageBenefitId IN :coverageBenefitIds];

            Set<Id> coverageBenefitItemIds = new Map<Id, CoverageBenefitItem>(coverageBenefitItems).keySet();

                
            // ── 4. ALL CoverageBenefitItemDetails for those Items ─────────────
            List<medicalcoverage__CoverageBenefitItemDetail__c> coverageBenefitItemDetails =
                coverageBenefitItemIds.isEmpty()
                ? new List<medicalcoverage__CoverageBenefitItemDetail__c>()
                : [SELECT Id, Name,
                          medicalcoverage__Coverage_Benefit_Item__c,
                          medicalcoverage__Cateogy__c,
                          Display_Category_New__c,
                          medicalcoverage__Value__c,
                          medicalcoverage__remainingAmount__c,
                          medicalcoverage__PayerNotes__c
                   FROM   medicalcoverage__CoverageBenefitItemDetail__c
                   WHERE  medicalcoverage__Coverage_Benefit_Item__c
                              IN :coverageBenefitItemIds];

            // ── Lookup Maps ───────────────────────────────────────────────────
            Map<Id, List<CoverageBenefit>> planToBenefitsMap =
                new Map<Id, List<CoverageBenefit>>();
            Map<Id, List<CoverageBenefitItem>> benefitToItemsMap =
                new Map<Id, List<CoverageBenefitItem>>();
            Map<Id, List<medicalcoverage__CoverageBenefitItemDetail__c>> itemToDetailsMap =
                new Map<Id, List<medicalcoverage__CoverageBenefitItemDetail__c>>();

            for (CoverageBenefit cb : coverageBenefits) {
                if (!planToBenefitsMap.containsKey(cb.MemberPlanId))
                    planToBenefitsMap.put(cb.MemberPlanId, new List<CoverageBenefit>());
                planToBenefitsMap.get(cb.MemberPlanId).add(cb);
            }
            for (CoverageBenefitItem cbi : coverageBenefitItems) {
                if (!benefitToItemsMap.containsKey(cbi.CoverageBenefitId))
                    benefitToItemsMap.put(cbi.CoverageBenefitId,
                        new List<CoverageBenefitItem>());
                benefitToItemsMap.get(cbi.CoverageBenefitId).add(cbi);
            }
            for (medicalcoverage__CoverageBenefitItemDetail__c cbid
                    : coverageBenefitItemDetails) {
                Id itemKey = cbid.medicalcoverage__Coverage_Benefit_Item__c;
                if (!itemToDetailsMap.containsKey(itemKey))
                    itemToDetailsMap.put(itemKey,
                        new List<medicalcoverage__CoverageBenefitItemDetail__c>());
                itemToDetailsMap.get(itemKey).add(cbid);
            }

            // ── Build JSON ────────────────────────────────────────────────────
            List<Map<String, Object>> plansList = new List<Map<String, Object>>();

            for (MemberPlan plan : memberPlans) {

                List<CoverageBenefit> planBenefits =
                    planToBenefitsMap.get(plan.Id);
                List<Map<String, Object>> coverageBenefitsList =
                    new List<Map<String, Object>>();

                if (planBenefits != null) {
                    for (CoverageBenefit cb : planBenefits) {

                        List<CoverageBenefitItem> benefitItems =
                            benefitToItemsMap.get(cb.Id);
                        List<Map<String, Object>> itemsList =
                            new List<Map<String, Object>>();

                        if (benefitItems != null) {
                            for (CoverageBenefitItem cbi : benefitItems) {

                                List<medicalcoverage__CoverageBenefitItemDetail__c> itemDetails =
                                    itemToDetailsMap.get(cbi.Id);
                                List<Map<String, Object>> detailsList =
                                    new List<Map<String, Object>>();

                                if (itemDetails != null) {
                                    for (medicalcoverage__CoverageBenefitItemDetail__c cbid
                                            : itemDetails) {
                                        detailsList.add(new Map<String, Object>{
                                            'CoverageBenefitItemDetailId' => cbid.Id,
                                            'Name'                  => cbid.Name,
                                            'CoverageBenefitItemId' =>
                                                cbid.medicalcoverage__Coverage_Benefit_Item__c,
                                            'Category'        => cbid.medicalcoverage__Cateogy__c,
                                            'DisplayCategory' => cbid.Display_Category_New__c,
                                            'TotalAmount'     => cbid.medicalcoverage__Value__c,
                                            'RemainingAmount' =>
                                                cbid.medicalcoverage__remainingAmount__c,
                                            'PayerNotes'      => cbid.medicalcoverage__PayerNotes__c
                                        });
                                    }
                                }

                                itemsList.add(new Map<String, Object>{
                                    'CoverageBenefitItemId' => cbi.Id,
                                    'Name'              => cbi.Name,
                                    'MemberId'          => cbi.MemberId,
                                    'CoverageBenefitId' => cbi.CoverageBenefitId,
                                    'CoverageBenefitItemDetails' => detailsList
                                });
                            }
                        }

                        coverageBenefitsList.add(new Map<String, Object>{
                            'CoverageBenefitId' => cb.Id,
                            'Name'              => cb.Name,
                            'MemberId'          => cb.MemberId,
                            'MemberPlanId'      => cb.MemberPlanId,
                            'Individual_In_Network_Deductible_Total' =>
                                cb.medicalcoverage__Individual_In_Network_Deductible_Total__c,
                            'Individual_In_Network_Deductible_Remaining' =>
                                cb.IndividualInNetworkDeductibleRemaining,
                            'Individual_In_Network_Deductible_Notes' =>
                                cb.medicalcoverage__Individual_In_Network_Deductible_Notes__c,
                            'Individual_Out_of_Network_Deductible_Total' =>
                                cb.medicalcoverage__Individual_Out_of_Network_Deductible_Tot__c,
                            'Individual_Out_of_Network_Deductible_Remaining' =>
                                cb.IndividualOutofNetworkDeductibleRemain,
                            'Individual_Out_of_Network_Deductible_Notes' =>
                                cb.medicalcoverage__Individual_OutofNetwork_Deductible_Note__c,
                            'Family_In_Network_Deductible_Total' =>
                                cb.medicalcoverage__Family_In_Network_Deductible_Total__c,
                            'Family_In_Network_Deductible_Remaining' =>
                                cb.FamilyInNetworkDeductibleRemaining,
                            'Family_In_Network_Deductible_Notes' =>
                                cb.medicalcoverage__Family_In_Network_Deductible_Notes__c,
                            'Family_Out_of_Network_Deductible_Total' =>
                                cb.medicalcoverage__Family_Out_of_Network_Deductible_Total__c,
                            'Family_Out_of_Network_Deductible_Remaining' =>
                                cb.FamilyOutofNetworkDeductibleRemaining,
                            'Family_Out_of_Network_Deductible_Notes' =>
                                cb.medicalcoverage__Family_Out_of_Network_Deductible_Notes__c,
                            'Individual_NAN_Deductible_Total' =>
                                cb.medicalcoverage__Individual_NAN_Deductible_Total__c,
                            'Individual_NAN_Deductible_Remaining' =>
                                cb.medicalcoverage__Individual_NAN_Deductible_Remaining__c,
                            'Individual_NAN_Deductible_Notes' =>
                                cb.medicalcoverage__Individual_NAN_Deductible_Notes__c,
                            'Family_NAN_Deductible_Total' =>
                                cb.medicalcoverage__Family_NAN_Deductible_Total__c,
                            'Family_NAN_Deductible_Remaining' =>
                                cb.medicalcoverage__Family_NAN_Deductible_Remaining__c,
                            'Family_NAN_Deductible_Notes' =>
                                cb.medicalcoverage__Family_NAN_Deductible_Notes__c,
                            'In_Network_Coinsurance_Amount'         =>
                                cb.InNetworkCoinsuranceAmount,
                            'Out_of_Network_Coinsurance_Amount'     =>
                                cb.OutofNetworkCoinsuranceAmount,
                            'In_Network_Coinsurance_Percentage'     =>
                                cb.InNetworkCoinsurancePercentage,
                            'Out_of_Network_Coinsurance_Percentage' =>
                                cb.OutofNetworkCoinsurancePercentage,
                            'Out_of_Network_Coinsurance_Notes' =>
                                cb.medicalcoverage__Out_of_Network_Coinsurance_Notes__c,
                            'Individual_In_Network_Out_of_Pocket_Total' =>
                                cb.medicalcoverage__Individual_In_Network_Out_of_Pocket_Tot__c,
                            'Individual_In_Network_Out_of_Pocket_Remaining' =>
                                cb.IndividualInNetworkOutofPocketRemaining,
                            'Individual_In_Network_Out_of_Pocket_Notes' =>
                                cb.medicalcoverage__Individual_In_Network_Out_of_Pocket_Note__c,
                            'Individual_Out_of_Network_Out_of_Pocket_Total' =>
                                cb.medicalcoverage__Individual_Out_Network_Out_Pocket_Total__c,
                            'Individual_Out_of_Network_Out_of_Pocket_Remaining' =>
                                cb.IndividualOutofNetworkOutofPocketRemain,
                            'Individual_Out_of_Network_Out_of_Pocket_Notes' =>
                                cb.medicalcoverage__Individual_Out_of_Network_Out_of_Pocket__c,
                            'Family_In_Network_Out_of_Pocket_Total' =>
                                cb.medicalcoverage__Family_In_Network_Out_of_Pocket_Total__c,
                            'Family_In_Network_Out_of_Pocket_Remaining' =>
                                cb.FamilyInNetworkOutofPocketRemaining,
                            'Family_In_Network_Out_of_Pocket_Notes' =>
                                cb.medicalcoverage__Family_In_Network_Out_of_Pocket_Notes__c,
                            'Family_Out_of_Network_Out_of_Pocket_Total' =>
                                cb.medicalcoverage__Family_Out_of_Network_Out_of_Pocket_Tot__c,
                            'Family_Out_of_Network_Out_of_Pocket_Remaining' =>
                                cb.FamilyOutofNetworkOutofPocketRemaining,
                            'Family_Out_of_Network_Out_of_Pocket_Notes' =>
                                cb.medicalcoverage__Family_Out_of_Network_Out_of_Pocket_Note__c,
                            'Individual_NAN_Out_of_Pocket_Total' =>
                                cb.medicalcoverage__Individual_NAN_Out_of_Pocket_Total__c,
                            'Individual_NAN_Out_of_Pocket_Remaining' =>
                                cb.medicalcoverage__IndividualNANOutofPocketRemaining__c,
                            'Individual_NAN_Out_of_Pocket_Notes' =>
                                cb.medicalcoverage__Individual_NAN_Out_of_Pocket_Note__c,
                            'Family_NAN_Out_of_Pocket_Total' =>
                                cb.medicalcoverage__Family_NAN_Out_of_Pocket_Total__c,
                            'Family_NAN_Out_of_Pocket_Remaining' =>
                                cb.medicalcoverage__FamilyNANOutofPocketRemaining__c,
                            'Family_NAN_Out_of_Pocket_Notes' =>
                                cb.medicalcoverage__Family_NAN_Out_of_Pocket_Notes__c,
                            'CoverageBenefitItems' => itemsList
                        });
                    }
                }

                plansList.add(new Map<String, Object>{
                    'MemberPlanId'             => plan.Id,
                    'Name'                     => plan.Name,
                    'MemberId'                 => plan.MemberId,
                    'PayerName'                => plan.medicalcoverage__Payer_Name__c,
                    'MemberNumber'             => plan.MemberNumber,
                    'GroupName'                => plan.medicalcoverage__Group_Name__c,
                    'GroupNumber'              => plan.GroupNumber,
                    'EffectiveFrom'            => plan.EffectiveFrom,
                    'AsOfDate'                 => plan.medicalcoverage__As_of_Date__c,
                    'InsuranceType'            =>
                        (planBenefits != null && !planBenefits.isEmpty())
                            ? planBenefits[0].medicalcoverage__InsuranceType__c
                            : null,
                    'GovernmentPayer'          => plan.medicalcoverage__Is_Government_Payer__c,
                    'RelationshipToSubscriber' => plan.RelationshipToSubscriber,
                    'Status'                   => plan.VerificationStatus,
                    'Gender'                   => plan.medicalcoverage__Gender__c,
                    'CreatedDate'              => plan.CreatedDate,
                    'CoverageBenefits'         => coverageBenefitsList
                });
            }

            String jsonBody = JSON.serializePretty(
                new Map<String, Object>{ 'Member_Plan' => plansList }
            );
            System.debug('MemberPlanCalloutFuture payload >>> ' + jsonBody);

            // ── Callout ───────────────────────────────────────────────────────
            BatonPortalAPI__c settings = BatonPortalAPI__c.getOrgDefaults();
            if (settings == null || String.isBlank(settings.Insurance_Key__c)) {
                System.debug('ERROR: BatonPortalAPI Insurance_Key__c not configured.');
                return;
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(settings.Insurance_Key__c);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept',       'application/json');
            req.setBody(jsonBody);
            req.setTimeout(120000);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                System.debug('API Error: ' + res.getStatusCode()
                             + ' - ' + res.getBody());
            } else {
                System.debug('Success: ' + memberPlans.size()
                             + ' MemberPlan(s) sent.');
            }

        } catch (Exception ex) {
            System.debug('MemberPlanCalloutFuture exception: '
                         + ex.getMessage() + ' | ' + ex.getStackTraceString());
        }
    }
}