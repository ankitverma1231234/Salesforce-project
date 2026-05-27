public with sharing class DocFlowEmailService {

    private static Boolean isRunning = false;

    private static final String PUBLIC_LINK_TEMPLATE_DEV_NAME = 'Docflow_Send_Template';
    private static final String COMPLETED_COPY_TEMPLATE_DEV_NAME = 'DocFlow_Completed_Copy';

    public static void sendPublicLinkEmails(
        List<Doc_Flow_Document__c> newList,
        Map<Id, Doc_Flow_Document__c> oldMap
    ) {
        if (isRunning) {
            return;
        }

        isRunning = true;
        try {
            List<Doc_Flow_Document__c> docsToSend = new List<Doc_Flow_Document__c>();
            Set<Id> accountIds = new Set<Id>();

            for (Doc_Flow_Document__c docRec : newList) {
                Doc_Flow_Document__c oldRec = oldMap != null ? oldMap.get(docRec.Id) : null;

                if (shouldSendPublicLinkEmail(docRec, oldRec)) {
                    docsToSend.add(docRec);

                    if (docRec.Account__c != null) {
                        accountIds.add(docRec.Account__c);
                    }
                }
            }

            if (docsToSend.isEmpty()) {
                return;
            }

            Id templateId = getTemplateIdByDeveloperName(PUBLIC_LINK_TEMPLATE_DEV_NAME);

            if (templateId == null) {
                updateDocErrors(
                    docsToSend,
                    'Email template not found: ' + PUBLIC_LINK_TEMPLATE_DEV_NAME
                );
                return;
            }

            Map<Id, Account> accountMap = new Map<Id, Account>([
                SELECT Id, Name, PersonContactId, PersonEmail, IsPersonAccount
                FROM Account
                WHERE Id IN :accountIds
            ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            List<Id> emailDocIds = new List<Id>();
            List<Doc_Flow_Document__c> preSendErrors = new List<Doc_Flow_Document__c>();

            for (Doc_Flow_Document__c docRec : docsToSend) {
                Account acc = accountMap.get(docRec.Account__c);

                if (acc == null) {
                    preSendErrors.add(new Doc_Flow_Document__c(
                        Id = docRec.Id,
                        Error_Message__c = 'Email send skipped: related Account not found.'
                    ));
                    continue;
                }

                if (!acc.IsPersonAccount) {
                    preSendErrors.add(new Doc_Flow_Document__c(
                        Id = docRec.Id,
                        Error_Message__c = 'Email send skipped: Account is not a Person Account.'
                    ));
                    continue;
                }

                if (acc.PersonContactId == null) {
                    preSendErrors.add(new Doc_Flow_Document__c(
                        Id = docRec.Id,
                        Error_Message__c = 'Email send skipped: PersonContactId is blank.'
                    ));
                    continue;
                }

                if (String.isBlank(acc.PersonEmail)) {
                    preSendErrors.add(new Doc_Flow_Document__c(
                        Id = docRec.Id,
                        Error_Message__c = 'Email send skipped: PersonEmail is blank.'
                    ));
                    continue;
                }

                if (String.isBlank(docRec.Primary_Access_Link__c)) {
                    preSendErrors.add(new Doc_Flow_Document__c(
                        Id = docRec.Id,
                        Error_Message__c = 'Email send skipped: Primary Access Link is blank.'
                    ));
                    continue;
                }

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(templateId);
                mail.setTargetObjectId(acc.PersonContactId);
                mail.setWhatId(docRec.Id);
                mail.setSaveAsActivity(false);
                mail.setTreatTargetObjectAsRecipient(true);

                emails.add(mail);
                emailDocIds.add(docRec.Id);
            }

            if (!preSendErrors.isEmpty()) {
                Database.update(preSendErrors, false);
            }

            if (emails.isEmpty()) {
                return;
            }

            Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

            List<Doc_Flow_Document__c> postSendUpdates = new List<Doc_Flow_Document__c>();

            for (Integer i = 0; i < results.size(); i++) {
                Messaging.SendEmailResult r = results[i];
                Id docId = emailDocIds[i];

                if (r.isSuccess()) {
                    postSendUpdates.add(new Doc_Flow_Document__c(
                        Id = docId,
                        Error_Message__c = null
                    ));
                } else {
                    String errorMessage = buildEmailErrorMessage(r);
                    postSendUpdates.add(new Doc_Flow_Document__c(
                        Id = docId,
                        Error_Message__c = safeTrim('Email send failed: ' + errorMessage, 32000)
                    ));
                }
            }

            if (!postSendUpdates.isEmpty()) {
                Database.update(postSendUpdates, false);
            }

        } finally {
            isRunning = false;
        }
    }

    public static void sendCompletedCopyEmailsFromWebhook() {
        // later
    }

    private static Boolean shouldSendPublicLinkEmail(
        Doc_Flow_Document__c newRec,
        Doc_Flow_Document__c oldRec
    ) {
        if (newRec == null) {
            return false;
        }

        if (newRec.Status__c != 'success') {
            return false;
        }

        if (String.isBlank(newRec.Primary_Access_Link__c)) {
            return false;
        }

        if (newRec.Account__c == null) {
            return false;
        }

        if (oldRec == null) {
            return true;
        }

        Boolean statusJustBecameSuccess =
            oldRec.Status__c != 'success' && newRec.Status__c == 'success';

        Boolean linkJustBecameAvailable =
            String.isBlank(oldRec.Primary_Access_Link__c) &&
            !String.isBlank(newRec.Primary_Access_Link__c);

        return statusJustBecameSuccess || linkJustBecameAvailable;
    }

    private static Id getTemplateIdByDeveloperName(String developerName) {
        List<EmailTemplate> templates = [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        return templates.isEmpty() ? null : templates[0].Id;
    }

    private static void updateDocErrors(List<Doc_Flow_Document__c> docs, String message) {
        List<Doc_Flow_Document__c> updates = new List<Doc_Flow_Document__c>();

        for (Doc_Flow_Document__c d : docs) {
            updates.add(new Doc_Flow_Document__c(
                Id = d.Id,
                Error_Message__c = safeTrim(message, 32000)
            ));
        }

        if (!updates.isEmpty()) {
            Database.update(updates, false);
        }
    }

    private static String buildEmailErrorMessage(Messaging.SendEmailResult result) {
        if (result == null || result.getErrors() == null || result.getErrors().isEmpty()) {
            return 'Unknown email error.';
        }

        List<String> messages = new List<String>();

        for (Messaging.SendEmailError err : result.getErrors()) {
            if (err == null) {
                continue;
            }

            String msg = '';
            if (err.getStatusCode() != null) {
                msg += String.valueOf(err.getStatusCode()) + ': ';
            }
            msg += err.getMessage();
            messages.add(msg);
        }

        return String.join(messages, ' | ');
    }

    private static String safeTrim(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        if (value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}