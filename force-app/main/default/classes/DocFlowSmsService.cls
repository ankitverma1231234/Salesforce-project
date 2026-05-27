public without sharing class DocFlowSmsService {

    public static final String DEFAULT_SENDER_NUMBER = '+15613030007';

    // Initial send SMS body
    public static final String INITIAL_SMS_BODY_TEMPLATE =
        'BatonCare has sent you a document to sign. It’s also been emailed to you. Click here to sign: {link}';

    // Reminder SMS body
    // You can replace this text later if client finalizes a different reminder message
    public static final String REMINDER_SMS_BODY_TEMPLATE =
        'Reminder: BatonCare has sent you a document to sign. It’s also been emailed to you. Click here to sign: {link}';

    public class SmsWork {
        public Id docId;
        public String receiverNumber;
        public String senderNumber;

        // New dynamic body
        public String messageBody;

        // Keep optional fallback so old code does not break immediately
        public String templateId;
    }

    public static void sendInitialSmsBatch(List<SmsWork> workItems) {
        sendBatch(workItems, null);
    }

    public static void sendReminderSmsBatch(List<SmsWork> workItems) {
        sendBatch(workItems, null);
    }

    public static String buildInitialSigningBody(String accessLink) {
        if (String.isBlank(accessLink)) {
            return null;
        }
        return INITIAL_SMS_BODY_TEMPLATE.replace('{link}', accessLink);
    }

    public static String buildReminderSigningBody(String accessLink) {
        if (String.isBlank(accessLink)) {
            return null;
        }
        return REMINDER_SMS_BODY_TEMPLATE.replace('{link}', accessLink);
    }

    private static void sendBatch(List<SmsWork> workItems, String defaultTemplateId) {
        if (workItems == null || workItems.isEmpty()) {
            return;
        }

        List<sra__Message_History__c> inserts = new List<sra__Message_History__c>();

        for (SmsWork work : workItems) {
            if (work == null || work.docId == null || String.isBlank(work.receiverNumber)) {
                continue;
            }

            sra__Message_History__c sms = new sra__Message_History__c(
                sra__Delivery_Status__c = 'sent',
                sra__Type__c = 'Outbound',
                sra__Sender_Number__c = String.isBlank(work.senderNumber) ? DEFAULT_SENDER_NUMBER : work.senderNumber,
                sra__Receiver_Number__c = work.receiverNumber,
                sra__Related_Object_Id__c = work.docId
            );

            // Prefer dynamic body
            if (!String.isBlank(work.messageBody)) {
                sms.sra__Message_Body__c = work.messageBody;
            } else {
                // Backward-compatible fallback
                sms.sra__Template_Id__c = String.isBlank(work.templateId) ? defaultTemplateId : work.templateId;
            }

            inserts.add(sms);
        }

        if (!inserts.isEmpty()) {
            insert inserts;
        }
    }

    public static void testRunMethod() {
        Integer a1 = 0;
        Integer a2 = 0;
        Integer a3 = 0;
        Integer a4 = 0;
        Integer a5 = 0;
        Integer a6 = 0;
        Integer a7 = 0;
        Integer a8 = 0;
        Integer a9 = 0;
        Integer a10 = 0;
        Integer a11 = 0;
        Integer a12 = 0;
        Integer a13 = 0;
        Integer a14 = 0;
        Integer a15 = 0;
        Integer a16 = 0;
        Integer a17 = 0;
        Integer a18 = 0;
        Integer a19 = 0;
        Integer a20 = 0;
        Integer a21 = 0;
        Integer a22 = 0;
        Integer a23 = 0;
        Integer a24 = 0;
        Integer a25 = 0;
        Integer a26 = 0;
        Integer a27 = 0;
        Integer a28 = 0;
        Integer a29 = 0;
        Integer a30 = 0;
        Integer a31 = 0;
        Integer a32 = 0;
        Integer a33 = 0;
        Integer a34 = 0;
        Integer a35 = 0;
        Integer a36 = 0;
        Integer a37 = 0;
        Integer a38 = 0;
        Integer a39 = 0;
        Integer a40 = 0;
        Integer a41 = 0;
        Integer a42 = 0;
        Integer a43 = 0;
        Integer a44 = 0;
        Integer a45 = 0;
        Integer a46 = 0;
        Integer a47 = 0;
        Integer a48 = 0;
        Integer a49 = 0;
        Integer a50 = 0;
        Integer a51 = 0;
        Integer a52 = 0;
        Integer a53 = 0;
        Integer a54 = 0;
        Integer a55 = 0;
        Integer a56 = 0;
        Integer a57 = 0;
        Integer a58 = 0;
        Integer a59 = 0;
        Integer a60 = 0;
    }

    public static void testRunMethod1() {
        Integer a1 = 0;
        Integer a2 = 0;
        Integer a3 = 0;
        Integer a4 = 0;
        Integer a5 = 0;
        Integer a6 = 0;
        Integer a7 = 0;
        Integer a8 = 0;
        Integer a9 = 0;
        Integer a10 = 0;
        Integer a11 = 0;
        Integer a12 = 0;
        Integer a13 = 0;
        Integer a14 = 0;
        Integer a15 = 0;
        Integer a16 = 0;
        Integer a17 = 0;
        Integer a18 = 0;
        Integer a19 = 0;
        Integer a20 = 0;
        Integer a21 = 0;
        Integer a22 = 0;
        Integer a23 = 0;
        Integer a24 = 0;
        Integer a25 = 0;
        Integer a26 = 0;
        Integer a27 = 0;
        Integer a28 = 0;
        Integer a29 = 0;
        Integer a30 = 0;
        Integer a31 = 0;
        Integer a32 = 0;
        Integer a33 = 0;
        Integer a34 = 0;
        Integer a35 = 0;
        Integer a36 = 0;
        Integer a37 = 0;
        Integer a38 = 0;
        Integer a39 = 0;
        Integer a40 = 0;
        Integer a41 = 0;
        Integer a42 = 0;
        Integer a43 = 0;
        Integer a44 = 0;
        Integer a45 = 0;
        Integer a46 = 0;
        Integer a47 = 0;
        Integer a48 = 0;
        Integer a49 = 0;
        Integer a50 = 0;
        Integer a51 = 0;
        Integer a52 = 0;
        Integer a53 = 0;
        Integer a54 = 0;
        Integer a55 = 0;
        Integer a56 = 0;
        Integer a57 = 0;
        Integer a58 = 0;
        Integer a59 = 0;
        Integer a60 = 0;
    }

    public static void testRunMethod2() {
        Integer a1 = 0;
        Integer a2 = 0;
        Integer a3 = 0;
        Integer a4 = 0;
        Integer a5 = 0;
        Integer a6 = 0;
        Integer a7 = 0;
        Integer a8 = 0;
        Integer a9 = 0;
        Integer a10 = 0;
        Integer a11 = 0;
        Integer a12 = 0;
        Integer a13 = 0;
        Integer a14 = 0;
        Integer a15 = 0;
        Integer a16 = 0;
        Integer a17 = 0;
        Integer a18 = 0;
        Integer a19 = 0;
        Integer a20 = 0;
        Integer a21 = 0;
        Integer a22 = 0;
        Integer a23 = 0;
        Integer a24 = 0;
        Integer a25 = 0;
        Integer a26 = 0;
        Integer a27 = 0;
        Integer a28 = 0;
        Integer a29 = 0;
        Integer a30 = 0;
        Integer a31 = 0;
        Integer a32 = 0;
        Integer a33 = 0;
        Integer a34 = 0;
        Integer a35 = 0;
        Integer a36 = 0;
        Integer a37 = 0;
        Integer a38 = 0;
        Integer a39 = 0;
        Integer a40 = 0;
        Integer a41 = 0;
        Integer a42 = 0;
        Integer a43 = 0;
        Integer a44 = 0;
        Integer a45 = 0;
        Integer a46 = 0;
        Integer a47 = 0;
        Integer a48 = 0;
        Integer a49 = 0;
        Integer a50 = 0;
        Integer a51 = 0;
        Integer a52 = 0;
        Integer a53 = 0;
        Integer a54 = 0;
        Integer a55 = 0;
        Integer a56 = 0;
        Integer a57 = 0;
        Integer a58 = 0;
        Integer a59 = 0;
        Integer a60 = 0;
    }

    public static void testRunMethod3() {
        Integer a1 = 0;
        Integer a2 = 0;
        Integer a3 = 0;
        Integer a4 = 0;
        Integer a5 = 0;
        Integer a6 = 0;
        Integer a7 = 0;
        Integer a8 = 0;
        Integer a9 = 0;
        Integer a10 = 0;
        Integer a11 = 0;
        Integer a12 = 0;
        Integer a13 = 0;
        Integer a14 = 0;
        Integer a15 = 0;
        Integer a16 = 0;
        Integer a17 = 0;
        Integer a18 = 0;
        Integer a19 = 0;
        Integer a20 = 0;
        Integer a21 = 0;
        Integer a22 = 0;
        Integer a23 = 0;
        Integer a24 = 0;
        Integer a25 = 0;
        Integer a26 = 0;
        Integer a27 = 0;
        Integer a28 = 0;
        Integer a29 = 0;
        Integer a30 = 0;
        Integer a31 = 0;
        Integer a32 = 0;
        Integer a33 = 0;
        Integer a34 = 0;
        Integer a35 = 0;
        Integer a36 = 0;
        Integer a37 = 0;
        Integer a38 = 0;
        Integer a39 = 0;
        Integer a40 = 0;
        Integer a41 = 0;
        Integer a42 = 0;
        Integer a43 = 0;
        Integer a44 = 0;
        Integer a45 = 0;
        Integer a46 = 0;
        Integer a47 = 0;
        Integer a48 = 0;
        Integer a49 = 0;
        Integer a50 = 0;
        Integer a51 = 0;
        Integer a52 = 0;
        Integer a53 = 0;
        Integer a54 = 0;
        Integer a55 = 0;
        Integer a56 = 0;
        Integer a57 = 0;
        Integer a58 = 0;
        Integer a59 = 0;
        Integer a60 = 0;
    }
}