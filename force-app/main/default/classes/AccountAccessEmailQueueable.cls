public without sharing class AccountAccessEmailQueueable {
    
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

    public static void sendEmails(Set<Id> relationshipIds) {

        
        Id portalUserId = null;
        try {
            BatonPortalAPI__c settings = BatonPortalAPI__c.getOrgDefaults();
            String guestUsername = settings.Guest_User__c;

            if (String.isNotBlank(guestUsername)) {
                List<User> users = [
                    SELECT Id
                    FROM   User
                    WHERE  Name     = :guestUsername.trim()
                    AND    IsActive = true
                    LIMIT  1
                ];
                if (!users.isEmpty()) {
                    portalUserId = users[0].Id;
                } else {
                    System.debug(LoggingLevel.WARN, 'No active user found for Guest_User__c: ' + guestUsername);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Custom setting / user fetch failed: ' + e.getMessage());
        }

        EmailTemplate tmpl;
        try {
            tmpl = [
                SELECT Id, Subject, HtmlValue, Body
                FROM   EmailTemplate
                WHERE  DeveloperName = :Label.Approval_Template
                LIMIT  1
            ];
        } catch (QueryException qe) {
            System.debug(LoggingLevel.ERROR, 'Template not found: ' + qe.getMessage());
            return;
        }

        // ── 3. Org-wide email address ─────────────────────────────────────────
        List<OrgWideEmailAddress> owea = [
            SELECT Id
            FROM   OrgWideEmailAddress
            WHERE  Address = 'support@batoncare.com'
            LIMIT  1
        ];

        Map<Id, Account_head_relationship__c> records = new Map<Id, Account_head_relationship__c>([
            SELECT Id,
                   CreatedById,
                   Member_Account__c,
                   Member_Account__r.PersonEmail,
                   Member_Account__r.Name,
                   Authorized_Account_Access__c,
                   Authorized_Account_Access__r.Name,
                   Authorized_Account_Access__r.PersonEmail,
                   Verification_Code__c,
                   Approval_Token__c,
                   Token_Expiry__c,
                   Request_Access__c
            FROM   Account_head_relationship__c
            WHERE  Id IN :relationshipIds
        ]);

        List<Messaging.SingleEmailMessage> outbound = new List<Messaging.SingleEmailMessage>();

        for (Account_head_relationship__c r : records.values()) {
            if (r.Request_Access__c != true) {
                System.debug(LoggingLevel.INFO,
                    'Skipping email – Request_Access__c is false for record: ' + r.Id);
                continue;
            }

            String toAddress = (r.Authorized_Account_Access__r != null)
                ? r.Authorized_Account_Access__r.PersonEmail
                : null;

            if (String.isBlank(toAddress)) {
                System.debug(LoggingLevel.WARN,
                    'Skipping – no PersonEmail on Authorized_Account_Access__r for record: ' + r.Id);
                continue;
            }

            Messaging.SingleEmailMessage msg;
            try {
                msg = Messaging.renderStoredEmailTemplate(tmpl.Id, null, r.Id);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'Template render failed for ' + r.Id + ': ' + ex.getMessage());
                continue;
            }

          
            Boolean isCreatedByPortalUser = portalUserId != null && r.CreatedById == portalUserId;
            
            if (isCreatedByPortalUser) {
                String currentHtml = msg.getHtmlBody();
                if (String.isNotBlank(currentHtml) && currentHtml.containsIgnoreCase('</body>')) {
                    msg.setHtmlBody(
                        currentHtml.replaceAll('(?i)</body>', BATON_FOOTER_HTML + '</body>')
                    );
                } else {
                    msg.setHtmlBody(
                        (String.isNotBlank(currentHtml) ? currentHtml : '') + BATON_FOOTER_HTML
                    );
                }
            }

            msg.setToAddresses(new List<String>{ toAddress });
            msg.setSaveAsActivity(false);

            if (!owea.isEmpty()) {
                msg.setOrgWideEmailAddressId(owea[0].Id);
            }

            outbound.add(msg);
        }

        if (!outbound.isEmpty()) {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(outbound, false);
            for (Messaging.SendEmailResult res : results) {
                if (!res.isSuccess()) {
                    for (Messaging.SendEmailError err : res.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'Email send failed: ' + err.getStatusCode() + ' – ' + err.getMessage());
                    }
                }
            }
        }
    }
}