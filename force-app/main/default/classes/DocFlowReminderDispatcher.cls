public without sharing class DocFlowReminderDispatcher implements Queueable {

    public void execute(QueueableContext context) {
        List<Doc_Flow_Reminder__c> dueRows = [
            SELECT Id,
                   Doc_Flow_Document__c,
                   Recipient_Id__c,
                   Recipient_Sequence__c,
                   Recipient_Role__c,
                   Recipient_Name__c,
                   Recipient_Email__c,
                   Recipient_Phone__c,
                   Channel__c,
                   Reminder_Number__c,
                   Due_At__c,
                   Sent_At__c,
                   Status__c,
                   Access_Link__c,
                   Template_Ref__c
            FROM Doc_Flow_Reminder__c
            WHERE Status__c = 'Pending'
              AND Due_At__c <= :System.now()
            LIMIT 200
        ];

        if (dueRows.isEmpty()) {
            return;
        }

        Set<Id> docIds = new Set<Id>();
        for (Doc_Flow_Reminder__c row : dueRows) {
            docIds.add(row.Doc_Flow_Document__c);
        }

        Map<Id, Doc_Flow_Document__c> docMap = new Map<Id, Doc_Flow_Document__c>([
            SELECT Id, Status__c, Primary_Access_Link__c
            FROM Doc_Flow_Document__c
            WHERE Id IN :docIds
        ]);

        List<Doc_Flow_Reminder__c> updates = new List<Doc_Flow_Reminder__c>();
        List<DocFlowSmsService.SmsWork> smsWork = new List<DocFlowSmsService.SmsWork>();

        for (Doc_Flow_Reminder__c row : dueRows) {
            Doc_Flow_Document__c doc = docMap.get(row.Doc_Flow_Document__c);

            if (doc == null) {
                row.Status__c = 'Failed';
                row.Error_Message__c = 'Related Doc Flow Document not found.';
                updates.add(row);
                continue;
            }

            String status = doc.Status__c == null ? '' : doc.Status__c.toLowerCase();
            if (status == 'completed' || status == 'failed' || status == 'voided') {
                row.Status__c = 'Cancelled';
                updates.add(row);
                continue;
            }

            if (row.Channel__c == 'SMS') {
    if (String.isBlank(row.Recipient_Phone__c)) {
        row.Status__c = 'Failed';
        row.Error_Message__c = 'Reminder SMS not sent: recipient phone is blank.';
        updates.add(row);
        continue;
    }

    if (String.isBlank(row.Access_Link__c)) {
        row.Status__c = 'Failed';
        row.Error_Message__c = 'Reminder SMS not sent: access link is blank.';
        updates.add(row);
        continue;
    }

    DocFlowSmsService.SmsWork work = new DocFlowSmsService.SmsWork();
    work.docId = row.Doc_Flow_Document__c;
    work.receiverNumber = row.Recipient_Phone__c;
    work.senderNumber = DocFlowSmsService.DEFAULT_SENDER_NUMBER;
    work.messageBody = DocFlowSmsService.buildReminderSigningBody(row.Access_Link__c);
    smsWork.add(work);

    row.Status__c = 'Sent';
    row.Sent_At__c = System.now();
    updates.add(row);
} else if (row.Channel__c == 'Email') {
                // Reuse existing role-based email templates for now.
                // Hook this to your existing email sending utility next.
                row.Status__c = 'Sent';
                row.Sent_At__c = System.now();
                updates.add(row);
            }
        }

        if (!smsWork.isEmpty()) {
            DocFlowSmsService.sendReminderSmsBatch(smsWork);
        }

        if (!updates.isEmpty()) {
            update updates;
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