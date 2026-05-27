({
    getUrlParameter: function(name) {
        name = name.replace(/[\[]/, '\\[').replace(/[\]]/, '\\]');
        var regex = new RegExp('[\\?&]' + name + '=([^&#]*)');
        var results = regex.exec(location.search);
        return results === null ? '' : decodeURIComponent(results[1].replace(/\+/g, ' '));
    },
    
    fetchMemberPlan: function(component, accountId) {
        console.log("=== Fetching MemberPlan for Account:", accountId);
        
        component.set("v.isLoading", true);
        component.set("v.errorMessage", "");
        
        var action = component.get("c.getMemberPlanId");
        action.setParams({
            accountId: accountId
        });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            console.log("Apex Response State:", state);
            
            if (state === "SUCCESS") {
                var memberPlanId = response.getReturnValue();
                console.log("MemberPlan ID received:", memberPlanId);
                
                if (memberPlanId && memberPlanId !== null && memberPlanId !== '') {
                    component.set("v.memberPlanId", memberPlanId);
                    console.log("MemberPlan ID set successfully:", memberPlanId);
                } else {
                    console.warn("No MemberPlan found for Account:", accountId);
                    component.set("v.errorMessage", "No Member Plan found for this Account");
                }
                
            } else if (state === "ERROR") {
                var errors = response.getError();
                var errorMessage = "Unknown error occurred";
                
                if (errors && errors[0] && errors[0].message) {
                    errorMessage = errors[0].message;
                }
                
                console.error("Error from Apex:", errorMessage);
                component.set("v.errorMessage", errorMessage);
            }
            
            // Always stop loading spinner
            component.set("v.isLoading", false);
            console.log("Loading complete");
        });
        
        $A.enqueueAction(action);
    }
})