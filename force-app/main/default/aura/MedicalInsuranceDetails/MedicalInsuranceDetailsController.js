({
    doInit: function(component, event, helper) {
        console.log("=== MedicalInsurancePublic Init ===");
        
        // Try to get MemberPlan ID directly first (if provided in URL)
        var memberPlanId = helper.getUrlParameter('memberPlanId');
        
        if (memberPlanId && memberPlanId !== '') {
            console.log("MemberPlan ID provided directly in URL:", memberPlanId);
            component.set("v.memberPlanId", memberPlanId);
            component.set("v.isLoading", false);
            return;
        }
        
        // If no MemberPlan ID, try to get Account ID
        var accountId = helper.getUrlParameter('id') || helper.getUrlParameter('accountId');
        
        console.log("Account ID from URL:", accountId);
        
        // Validate Account ID
        if (!accountId || accountId === '') {
            component.set("v.errorMessage", "No Account ID provided in URL. Please add ?id=ACCOUNT_ID to the URL.");
            component.set("v.isLoading", false);
            console.error("No Account ID in URL");
            return;
        }
        
        component.set("v.accountId", accountId);
        
        // Fetch Member Plan using Apex
        helper.fetchMemberPlan(component, accountId);
    }
})