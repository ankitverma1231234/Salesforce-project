public without sharing class AccountOnboardingNotificationController {

    @AuraEnabled
    public static void sendOnboardingLink(Id accountId) {

        try {

            // =========================
            // FETCH ACCOUNT
            // =========================
            Account acc = [
                SELECT Id, Name, IsPersonAccount,
                       PersonEmail, PersonContactId,
                       Phone, Onboarding_URL__c
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];

            if (!acc.IsPersonAccount) {
                throw new AuraHandledException('Account must be Person Account.');
            }

            if (String.isBlank(acc.Onboarding_URL__c)) {
                throw new AuraHandledException('Onboarding URL is missing.');
            }

            // =========================
            // FETCH SENDER CONFIG
            // =========================
            sra__Message_User_Configuration__c senderConfig;

            List<sra__Message_User_Configuration__c> configs = [
                SELECT sra__Sender_Number__c
                FROM sra__Message_User_Configuration__c
                LIMIT 1
            ];

            if (!configs.isEmpty()) {
                senderConfig = configs[0];
            }

            List<sra__Message_History__c> smsRecords = new List<sra__Message_History__c>();
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            // =========================
            // FETCH SMS TEMPLATE
            // =========================

            String smsBody;

            List<sra__Message_Template__c> smsTemplates = [
                SELECT Id, Name, sra__Template_Body__c
                FROM sra__Message_Template__c
                WHERE Name = 'Onboarding Email SMS'
                LIMIT 1
            ];

            if (!smsTemplates.isEmpty()) {

                smsBody = smsTemplates[0].sra__Template_Body__c;

                // Replace Merge Fields
                smsBody = smsBody.replace('{!Name}', acc.Name);
               smsBody = smsBody.replace('{!Onboarding_URL__c}', acc.Onboarding_URL__c);
                system.debug('url aaya ya nhi' + smsBody);

            } else {
                System.debug('SMS Template Not Found');
            }

            // =========================
            // CREATE SMS RECORD
            // =========================

            if (senderConfig != null &&
                String.isNotBlank(acc.Phone) &&
                String.isNotBlank(smsBody)) {

                smsRecords.add(new sra__Message_History__c(
                    sra__Type__c              = 'Outbound',
                    sra__Sender_Number__c     = senderConfig.sra__Sender_Number__c,
                    sra__Receiver_Number__c   = acc.Phone,
                    sra__Message_Body__c      = smsBody,
                    sra__Delivery_Status__c   = 'sent',
                    sra__Related_Object_Id__c = acc.Id
                ));

            } else {
                System.debug('SMS Skipped: Missing Config, Phone, or Template');
            }

            // =========================
            // FETCH EMAIL TEMPLATE
            // =========================

            Id templateId;

            List<EmailTemplate> templates = [
                SELECT Id
                FROM EmailTemplate
                WHERE Name = 'Onboarding URL Message'
                LIMIT 1
            ];

            if (!templates.isEmpty()) {
                templateId = templates[0].Id;
            }

            // =========================
            // PREPARE EMAIL
            // =========================

            if (templateId != null &&
                String.isNotBlank(acc.PersonEmail) &&
                acc.PersonContactId != null) {

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(templateId);
                mail.setTargetObjectId(acc.PersonContactId);
                mail.setWhatId(acc.Id);
                mail.setSaveAsActivity(false);
                mail.setOrgWideEmailAddressId('0D2Kc000000Kym3KAC'); // Keep dynamic if possible

                emails.add(mail);

            } else {
                System.debug('Email Skipped: Template Missing or Contact Missing');
            }

            // =========================
            // EXECUTE DML
            // =========================

            if (!smsRecords.isEmpty()) {
                insert smsRecords;
            }

            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails, false);
            }

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}