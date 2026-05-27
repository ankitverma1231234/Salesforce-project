public without sharing class DocFlowReminderService {

    public static void activateInitialRecipientReminders(List<Doc_Flow_Document__c> docs) {
        if (docs == null || docs.isEmpty()) {
            return;
        }

        for (Doc_Flow_Document__c doc : docs) {
            if (doc == null || String.isBlank(doc.Recipient_Config_Json__c)) {
                continue;
            }

            Map<String, Object> config;
            try {
                config = (Map<String, Object>) JSON.deserializeUntyped(doc.Recipient_Config_Json__c);
            } catch (Exception ex) {
                continue;
            }

            Map<String, Object> reminderSettings = (Map<String, Object>) config.get('reminderSettings');
            if (reminderSettings == null || !normalizeBoolean(reminderSettings.get('enabled'))) {
                continue;
            }

            Integer intervalDays = normalizeInteger(reminderSettings.get('intervalDays'));
            Integer maxReminders = normalizeInteger(reminderSettings.get('maxReminders'));

            if (intervalDays == null || intervalDays < 1 || maxReminders == null || maxReminders < 1) {
                continue;
            }

            List<Object> recipients = (List<Object>) config.get('recipients');
            if (recipients == null || recipients.isEmpty()) {
                continue;
            }

            Map<String, Object> firstRecipient = null;
            Integer minSeq = null;

            for (Object rowObj : recipients) {
                if (!(rowObj instanceof Map<String, Object>)) continue;
                Map<String, Object> row = (Map<String, Object>) rowObj;
                Integer seq = normalizeInteger(row.get('sequence'));
                if (seq == null) continue;

                if (minSeq == null || seq < minSeq) {
                    minSeq = seq;
                    firstRecipient = row;
                }
            }

            if (firstRecipient == null) {
                continue;
            }

            activateRecipientReminders(
                doc.Id,
                safeString(firstRecipient.get('recipientId')),
                normalizeInteger(firstRecipient.get('sequence')),
                safeString(firstRecipient.get('role')),
                extractResolvedValue(firstRecipient.get('name')),
                extractResolvedValue(firstRecipient.get('email')),
                extractResolvedValue(firstRecipient.get('phone')),
                doc.Primary_Access_Link__c
            );
        }
    }

    public static void activateRecipientReminders(
        Id docId,
        String recipientId,
        Integer sequence,
        String role,
        String name,
        String email,
        String phone,
        String accessLink
    ) {
        if (docId == null || String.isBlank(recipientId)) {
            return;
        }

        Doc_Flow_Document__c doc = [
            SELECT Id, Recipient_Config_Json__c, Status__c
            FROM Doc_Flow_Document__c
            WHERE Id = :docId
            LIMIT 1
        ];

        if ('voided' == String.valueOf(doc.Status__c).toLowerCase()) {
            return;
        }

        Map<String, Object> config;
        try {
            config = (Map<String, Object>) JSON.deserializeUntyped(doc.Recipient_Config_Json__c);
        } catch (Exception ex) {
            return;
        }

        Map<String, Object> reminderSettings = (Map<String, Object>) config.get('reminderSettings');
        if (reminderSettings == null || !normalizeBoolean(reminderSettings.get('enabled'))) {
            return;
        }

        Integer intervalDays = normalizeInteger(reminderSettings.get('intervalDays'));
        Integer maxReminders = normalizeInteger(reminderSettings.get('maxReminders'));

        if (intervalDays == null || intervalDays < 1 || maxReminders == null || maxReminders < 1) {
            return;
        }

        List<Doc_Flow_Reminder__c> inserts = new List<Doc_Flow_Reminder__c>();
        Datetime nowDt = System.now();

        for (Integer i = 1; i <= maxReminders; i++) {
            Datetime dueAt = nowDt.addDays(intervalDays * i);

            if (!String.isBlank(email)) {
                inserts.add(buildReminder(
                    docId, recipientId, sequence, role, name, email, phone, 'Email', i, dueAt, accessLink
                ));
            }

            if (!String.isBlank(phone)) {
                inserts.add(buildReminder(
                    docId, recipientId, sequence, role, name, email, phone, 'SMS', i, dueAt, accessLink
                ));
            }
        }

        if (!inserts.isEmpty()) {
            Database.insert(inserts, false);
        }
    }

    public static void cancelPendingRemindersForDocument(Id docId) {
        if (docId == null) {
            return;
        }

        List<Doc_Flow_Reminder__c> rows = [
            SELECT Id, Status__c
            FROM Doc_Flow_Reminder__c
            WHERE Doc_Flow_Document__c = :docId
              AND Status__c = 'Pending'
        ];

        for (Doc_Flow_Reminder__c row : rows) {
            row.Status__c = 'Cancelled';
        }

        if (!rows.isEmpty()) {
            update rows;
        }
    }

    private static Doc_Flow_Reminder__c buildReminder(
        Id docId,
        String recipientId,
        Integer sequence,
        String role,
        String name,
        String email,
        String phone,
        String channel,
        Integer reminderNo,
        Datetime dueAt,
        String accessLink
    ) {
        Doc_Flow_Reminder__c row = new Doc_Flow_Reminder__c();
        row.Doc_Flow_Document__c = docId;
        row.Recipient_Id__c = recipientId;
        row.Recipient_Sequence__c = sequence;
        row.Recipient_Role__c = role;
        row.Recipient_Name__c = name;
        row.Recipient_Email__c = email;
        row.Recipient_Phone__c = phone;
        row.Channel__c = channel;
        row.Reminder_Number__c = reminderNo;
        row.Due_At__c = dueAt;
        row.Status__c = 'Pending';
        row.Access_Link__c = accessLink;
        row.Template_Ref__c = channel == 'SMS'
    ? 'DYNAMIC_SMS_BODY'
    : 'ROLE_BASED_EMAIL';
        row.Recipient_Key__c = recipientId + '|' + String.valueOf(sequence);
        row.Unique_Key__c =
            String.valueOf(docId) + '|' +
            recipientId + '|' +
            channel + '|' +
            String.valueOf(reminderNo);

        return row;
    }

    private static String extractResolvedValue(Object rawSection) {
        if (rawSection == null) return null;
        if (rawSection instanceof Map<String, Object>) {
            Map<String, Object> section = (Map<String, Object>) rawSection;
            Object value = section.get('resolvedValue');
            return value == null ? null : String.valueOf(value);
        }
        return String.valueOf(rawSection);
    }

    private static Boolean normalizeBoolean(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean) value;
        return 'true' == String.valueOf(value).toLowerCase();
    }

    private static Integer normalizeInteger(Object value) {
        if (value == null) return null;
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Long) return Integer.valueOf(String.valueOf(value));
        if (value instanceof Decimal) return ((Decimal) value).intValue();
        return Integer.valueOf(String.valueOf(value));
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}