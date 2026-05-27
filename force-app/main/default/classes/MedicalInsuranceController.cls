public without sharing class MedicalInsuranceController {
    
    @AuraEnabled
    public static String getMemberPlanId(String accountId) {
        System.debug('=== getMemberPlanId called ===');
        System.debug('Input accountId: ' + accountId);
        
        try {
            if (String.isBlank(accountId)) {
                System.debug('ERROR: Account ID is blank');
                throw new AuraHandledException('Account ID is required');
            }
            
            // Query MemberPlan using MemberId field (which stores Account ID)
            List<MemberPlan> memberPlans = [
                SELECT Id, Name, MemberId
                FROM MemberPlan 
                WHERE MemberId = :accountId 
                LIMIT 1
            ];
            
            System.debug('Query executed. Found ' + memberPlans.size() + ' record(s)');
            
            if (!memberPlans.isEmpty()) {
                String planId = memberPlans[0].Id;
                System.debug('SUCCESS: Returning MemberPlan Id: ' + planId);
                return planId;
            } else {
                System.debug('WARNING: No MemberPlan found for MemberId: ' + accountId);
                return null;
            }
            
        } catch (Exception e) {
            System.debug('EXCEPTION in getMemberPlanId: ' + e.getMessage());
            System.debug('Exception Type: ' + e.getTypeName());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error fetching Member Plan: ' + e.getMessage());
        }
    }
}