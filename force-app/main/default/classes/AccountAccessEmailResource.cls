@RestResource(urlMapping='/AccountAccessEmail/*')
global without sharing class AccountAccessEmailResource {
    
    private static final String SUPPORT_EMAIL_ADDRESS = 'support@batoncare.com';
    
    private static final String BATON_FOOTER_HTML = 
        '<br/><br/>' +
        '<div style="color:#555;font-size:12px;border-top:1px solid #ccc;padding-top:8px;">' +
            '<img src="https://batoncare.com/wp-content/uploads/2025/06/Logo.png" style="max-height:40px;margin-bottom:8px;"/><br/>' +
            'You are receiving this email because you opted in via our website or prior communications.<br/>' +
            'To unsubscribe, email &quot;Unsubscribe&quot; to <a href="mailto:support@batoncare.com">support@batoncare.com</a>.<br/><br/>' +
            '<em>This email and any attachments may contain confidential or legally protected information intended solely for the use of the individual or entity to whom it is addressed. ' +
            'If you are not the intended recipient, please notify the sender immediately and delete this message. ' +
            'Any unauthorized review, use, disclosure, or distribution is prohibited.</em><br/><br/>' +
            '&copy; 2026 BatonCare | 980 North Federal Highway, Suite 110 #1068, Boca Raton, FL 33432 | ' +
            '<a href="mailto:support@batoncare.com">support@batoncare.com</a>' +
        '</div>';

    global class AccessEmailRequest {
        public String  name;
        public String  accountId;
        public Boolean give_access;
        public Boolean request_access;
        public String  headAccountName;
    }

    global class AccessEmailResponse {
        public Boolean success;
        public String  message;

        public AccessEmailResponse(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }

    private class AHRAccountWrapper {
        public Id       ahrId; 
        public Id       memberId;
        public String   personEmail;
        public String   firstName;
        public String   lastName;
        public String   verificationCode;
        public String   approvalToken;
        public Datetime tokenExpiry;
        public String   headAccountName;
        public String   childAccountName;
    }

    @HttpPost
    global static void sendAccessEmail() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            AccessEmailRequest requestPayload = parseRequest();
            String validationMessage = validateRequest(requestPayload);

            if (validationMessage != null) {
                writeResponse(400, false, validationMessage);
                return;
            }

            AHRAccountWrapper wrapper = getAccountFromAHR(requestPayload.accountId);
            if (wrapper == null) {
                writeResponse(404, false, 'No Account Head Relationship found for the given accountId.');
                return;
            }

            if (String.isBlank(wrapper.personEmail)) {
                writeResponse(400, false, 'PersonEmail is blank for the Member Account.');
                return;
            }

            String templateDeveloperName = getTemplateDeveloperName(requestPayload);
            EmailTemplate templateRecord = getEmailTemplate(templateDeveloperName);
            if (templateRecord == null) {
                writeResponse(404, false, 'Email template not found: ' + templateDeveloperName);
                return;
            }

            List<OrgWideEmailAddress> orgWideEmailAddresses = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = :SUPPORT_EMAIL_ADDRESS
                LIMIT 1
            ];

            if (orgWideEmailAddresses.isEmpty()) {
                writeResponse(500, false, 'Org-Wide Email Address not found.');
                return;
            }

            sendEmail(wrapper, templateRecord.Id, orgWideEmailAddresses[0].Id);
            writeResponse(200, true, 'Email sent successfully.');

        } catch (Exception ex) {
            writeResponse(500, false, 'Error: ' + ex.getMessage());
        }
    }

    private static AccessEmailRequest parseRequest() {
        String requestBody = RestContext.request.requestBody == null
            ? null
            : RestContext.request.requestBody.toString();

        return (AccessEmailRequest) JSON.deserialize(requestBody, AccessEmailRequest.class);
    }

    // ── Validate Request ──────────────────────────────────────────────────────
    private static String validateRequest(AccessEmailRequest requestPayload) {
        if (requestPayload == null) {
            return 'Request body is required.';
        }
        if (String.isBlank(requestPayload.accountId)) {
            return 'Missing accountId.';
        }
        if (requestPayload.give_access != true && requestPayload.request_access != true) {
            return 'Either give_access or request_access must be true.';
        }
        return null;
    }

    private static AHRAccountWrapper getAccountFromAHR(String accountId) {
        List<Account_Head_Relationship__c> ahrList = [
            SELECT Id,
                   Member_Account__c,
                   Member_Account__r.Id,
                   Authorized_Account_Access__r.PersonEmail,
                   Member_Account__r.FirstName,
                   Member_Account__r.LastName,
                   Verification_Code__c,
                   Token_Expiry__c,
                   Approval_Token__c,
                   Head_Account_Name__c,
                   Child_Account_Name__c
            FROM Account_Head_Relationship__c
            WHERE Authorized_Account_Access__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (ahrList.isEmpty()) return null;

        Account_Head_Relationship__c ahr = ahrList[0];

        if (ahr.Authorized_Account_Access__c == null) return null;

        AHRAccountWrapper wrapper = new AHRAccountWrapper();
        wrapper.ahrId            = ahr.Id;
        wrapper.memberId          = ahr.Member_Account__r.Id;
        wrapper.personEmail       = ahr.Authorized_Account_Access__r.PersonEmail;
        wrapper.firstName         = ahr.Member_Account__r.FirstName;
        wrapper.lastName          = ahr.Member_Account__r.LastName;
        wrapper.verificationCode  = ahr.Verification_Code__c;
        wrapper.approvalToken     = ahr.Approval_Token__c;
        wrapper.tokenExpiry       = ahr.Token_Expiry__c;
        wrapper.headAccountName   = ahr.Head_Account_Name__c;
        wrapper.childAccountName  = ahr.Child_Account_Name__c;

        return wrapper;
    }

    // ── Pick Template ─────────────────────────────────────────────────────────
    private static String getTemplateDeveloperName(AccessEmailRequest requestPayload) {
        if (requestPayload.give_access == true) {
            return Label.Member_Approval_Template;
        }
        return Label.Approval_Template;
    }

    private static EmailTemplate getEmailTemplate(String templateDeveloperName) {
        if (String.isBlank(templateDeveloperName)) return null;

        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :templateDeveloperName
            LIMIT 1
        ];

        return templates.isEmpty() ? null : templates[0];
    }

    // ── Send Email ────────────────────────────────────────────────────────────
    private static void sendEmail(
        AHRAccountWrapper wrapper,
        Id templateId,
        Id orgWideEmailAddressId
    ) {
        Messaging.SingleEmailMessage message = Messaging.renderStoredEmailTemplate(
            templateId,
            null,
           wrapper.ahrId
        );

        String existingHtmlBody = message.getHtmlBody();
        if (existingHtmlBody == null) existingHtmlBody = '';
        message.setHtmlBody(existingHtmlBody + BATON_FOOTER_HTML);

        message.setToAddresses(new List<String>{ wrapper.personEmail });
        message.setSaveAsActivity(false);

        if (orgWideEmailAddressId != null) {
            message.setOrgWideEmailAddressId(orgWideEmailAddressId);
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ message },
            false
        );

        if (results.isEmpty() || !results[0].isSuccess()) {
            String errorMessage = 'Unknown email error.';
            if (!results.isEmpty() && !results[0].getErrors().isEmpty()) {
                errorMessage = results[0].getErrors()[0].getMessage();
            }
            throw new EmailSendException(errorMessage);
        }
    }

    private static void writeResponse(Integer statusCode, Boolean success, String message) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody = Blob.valueOf(
            JSON.serialize(new AccessEmailResponse(success, message))
        );
    }

    private class EmailSendException extends Exception {}
}