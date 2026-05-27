public without sharing class AccountAccessApprovalController {

    private static final String STATUS_PENDING  = 'Pending';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Denied';

    private static final String ACTION_APPROVE = 'approve';
    private static final String ACTION_REJECT  = 'reject';

    @AuraEnabled(cacheable=false)
    public static TokenInfo validateToken(String token) {
        if (String.isBlank(token)) {
            throw auraError('Missing token.');
        }

        List<Account_head_relationship__c> recs = [
            SELECT Id, Portal_Access_Status__c, Token_Expiry__c,
            Member_Account__r.Name, 
            Authorized_Account_Access__r.FirstName, 
            Authorized_Account_Access__r.LastName 
            FROM   Account_head_relationship__c
            WHERE  Approval_Token__c = :token
            LIMIT  1
        ];

        if (recs.isEmpty()) {
            throw auraError('This link is invalid or has already been used.');
        }

        Account_head_relationship__c r = recs[0];
        TokenInfo info = new TokenInfo();
        info.status           = r.Portal_Access_Status__c;
        info.expired          = r.Token_Expiry__c == null || r.Token_Expiry__c < Datetime.now();
        info.alreadyProcessed = r.Portal_Access_Status__c != STATUS_PENDING;
        info.requestorName    = r.Member_Account__r != null ? r.Member_Account__r.Name : '';
        info.memberFirstName  = r.Authorized_Account_Access__r != null ? r.Authorized_Account_Access__r.FirstName : '';
        info.memberLastName   = r.Authorized_Account_Access__r != null ? r.Authorized_Account_Access__r.LastName  : '';
        
        return info;
    }

    @AuraEnabled
    public static ApprovalResult processApproval(String token, String action, String verificationCode) {
        if (String.isBlank(token))            { throw auraError('Missing token.'); }
        if (String.isBlank(action))           { throw auraError('Missing action.'); }
        if (String.isBlank(verificationCode)) { throw auraError('Please enter the verification code.'); }

        String normalized = action.toLowerCase();
        if (normalized != ACTION_APPROVE && normalized != ACTION_REJECT) {
            throw auraError('Unsupported action.');
        }

        List<Account_head_relationship__c> recs = [
            SELECT Id, Portal_Access_Status__c, Verification_Code__c, Token_Expiry__c
            FROM   Account_head_relationship__c
            WHERE  Approval_Token__c = :token
            LIMIT  1
            FOR UPDATE
        ];

        if (recs.isEmpty()) {
            throw auraError('This link is invalid or has already been used.');
        }

        Account_head_relationship__c r = recs[0];

        if (r.Token_Expiry__c == null || r.Token_Expiry__c < Datetime.now()) {
            throw auraError('This request has expired. Please ask the requestor to try again.');
        }
        if (r.Portal_Access_Status__c != STATUS_PENDING) {
            throw auraError('This request has already been ' + r.Portal_Access_Status__c.toLowerCase() + '.');
        }
        if (r.Verification_Code__c == null || r.Verification_Code__c != verificationCode.trim()) {
            throw auraError('The verification code is incorrect.');
        }

        r.Portal_Access_Status__c = (normalized == ACTION_APPROVE) ? STATUS_APPROVED : STATUS_REJECTED;
        r.Approval_Token__c = null;
        update r;

        ApprovalResult out = new ApprovalResult();
        out.success = true;
        out.status  = r.Portal_Access_Status__c;
        out.message = (normalized == ACTION_APPROVE)
            ? 'Access approved. Thank you.'
            : 'Request rejected. The requestor will not be granted access.';
        return out;
    }

    private static AuraHandledException auraError(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    public class TokenInfo {
        @AuraEnabled public String  status;
        @AuraEnabled public Boolean expired;
        @AuraEnabled public Boolean alreadyProcessed;
        @AuraEnabled public String  requestorName;
        @AuraEnabled public String  memberFirstName;
        @AuraEnabled public String  memberLastName;
    }

    public class ApprovalResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  status;
        @AuraEnabled public String  message;
    }
}