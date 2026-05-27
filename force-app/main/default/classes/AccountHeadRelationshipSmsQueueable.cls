public without sharing class AccountHeadRelationshipSmsQueueable {

    @future(callout=false)
    public static void sendSms(Set<Id> relationshipIds) {
        if (relationshipIds == null || relationshipIds.isEmpty()) return;
        User automatedUser = [
            SELECT Id, Name
            FROM   User
            WHERE  Name = 'Automated Process'
            LIMIT  1];

        List<SMS_Configuration__mdt> configs = [
            SELECT Sender_Number__c, SMS_Body_Template__c, Is_Active__c
            FROM   SMS_Configuration__mdt
            WHERE  Is_Active__c = true
            AND    DeveloperName = 'SMS_Body_Template'
            LIMIT  1
        ];

        if (configs.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'No active SMS_Configuration__mdt record found.');
            return;
        }

        String bodyTemplate  = configs[0].SMS_Body_Template__c;
        String senderNumber  = configs[0].Sender_Number__c;

        List<Account_Head_Relationship__c> records = [
            SELECT Id,
                   Name,
                   Approval_Token__c,
                   Verification_Code__c,
                   Token_Expiry__c,
                   Portal_Access_Status__c,
                   Authorized_Account_Access__c,
                   Authorized_Account_Access__r.Name,
                   Authorized_Account_Access__r.PersonMobilePhone,
                   Authorized_Account_Access__r.PersonEmail,
                   Member_Account__c,
                   Member_Account__r.Name,
                   Head_Phone_Number__c,
                   Request_Access__c  
            FROM   Account_Head_Relationship__c
            WHERE  Id IN :relationshipIds
            AND    Portal_Access_Status__c = 'Pending'
            AND    Approval_Token__c != null AND Request_Access__c = true];

        if (records.isEmpty()) return;

        // ── Duplicate Check (outside loop) ───────────────────────────────
        Set<Id> alreadySent = new Set<Id>();
        for (sra__Message_History__c m : [
            SELECT Account_Head_Relationship__c
            FROM   sra__Message_History__c
            WHERE  Account_Head_Relationship__c IN :relationshipIds
            AND    sra__Type__c = 'Outbound'
            ORDER BY CreatedDate DESC
            LIMIT  1000
        ]) {
            alreadySent.add(m.Account_Head_Relationship__c);
        }

        // ── Build SMS Records ────────────────────────────────────────────
        List<sra__Message_History__c> toInsert = new List<sra__Message_History__c>();

        for (Account_Head_Relationship__c r : records) {

            if (alreadySent.contains(r.Id)) {
                System.debug(LoggingLevel.WARN, 'Duplicate SMS skipped for: ' + r.Id);
                continue;
            }

            String toPhone = r.Authorized_Account_Access__r?.PersonMobilePhone;
            if (String.isBlank(toPhone)) {
                System.debug(LoggingLevel.WARN, 'No phone for rel: ' + r.Id);
                continue;
            }

            if (String.isBlank(r.Approval_Token__c)) {
                System.debug(LoggingLevel.WARN, 'Token still null for rel: ' + r.Id);
                continue;
            }

            String body = buildSmsBody(r, bodyTemplate);

            toInsert.add(new sra__Message_History__c(
                Name                         = 'Outbound',
                sra__Person_Name__c          = r.Name,
                sra__Type__c                 = 'Outbound',
                sra__Receiver_Number__c      = toPhone,
                sra__Sender_Number__c        = senderNumber,
                sra__Message_Body__c         = body,
                sra__Delivery_Status__c      = 'sent',
                sra__Related_Object_Id__c    = r.Id,
                Account_Head_Relationship__c = r.Id,
                CreatedById                  = automatedUser.Id,
                LastModifiedById             = automatedUser.Id
            ));
        }

        if (!toInsert.isEmpty()) {
            try {
                insert toInsert;
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'SMS insert failed: ' + ex.getMessage());
            }
        }
    }

    // ── Build SMS Body ───────────────────────────────────────────────────
    @TestVisible
    private static String buildSmsBody(Account_Head_Relationship__c r, String bodyTemplate) {

        String baseUrl  = Label.Site_Base_URL;
        String encoded  = EncodingUtil.urlEncode(r.Approval_Token__c, 'UTF-8');

        String approveUrl       = baseUrl + '?token=' + encoded + '&action=approve';
        String rejectUrl        = baseUrl + '?token=' + encoded + '&action=reject';
        String requestorName    = r.Member_Account__r?.Name   != null ? r.Member_Account__r.Name : '';
        String expiry           = r.Token_Expiry__c           != null
                                    ? r.Token_Expiry__c.format('MM/dd/yyyy', 'America/New_York') : '';
        String verificationCode = String.isNotBlank(r.Verification_Code__c) ? r.Verification_Code__c : '';

        return bodyTemplate
            .replace('{RequestorName}',    requestorName)
            .replace('{VerificationCode}', verificationCode)
            .replace('{ApproveUrl}',       approveUrl)
            .replace('{DenyUrl}',          rejectUrl)
            .replace('{Expiry}',           expiry);
    }
}