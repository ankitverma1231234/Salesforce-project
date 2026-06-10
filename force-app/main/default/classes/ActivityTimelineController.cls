public with sharing class ActivityTimelineController {
    @AuraEnabled  // Remove cacheable=true
    public static List<ActivityWrapper> getActivities(Id recordId, Integer limitSize, Integer offsetSize) {
        // Map for Duplicate Emailmessage
        Map<String, EmailMessage> uniqueEmails = new Map<String, EmailMessage>();
        if (limitSize == null) limitSize = 20;
        if (offsetSize == null) offsetSize = 0;
        
        List<ActivityWrapper> activities = new List<ActivityWrapper>();
        
        // --- TASKS ---
        List<Task> tasks = [
            SELECT Id, Subject, Status, Priority, CreatedDate
            FROM Task
            WHERE WhatId = :recordId AND TaskSubtype != 'Call'
            ORDER BY CreatedDate DESC 
            LIMIT :limitSize OFFSET :offsetSize
        ];
        for (Task t : tasks) {
            activities.add(new ActivityWrapper(
                t.Id, 
                'Task', 
                t.Subject, 
                t.Status, 
                t.Priority, 
                t.CreatedDate
            ));
        }
        
        // --- CASES (split by Case_Type__c: Metriport Cases and Portal Messages) ---
        List<Case> cases = [
            SELECT Id, Subject, Status, Priority, Description, CreatedDate, Case_Type__c
            FROM Case
            WHERE AccountId = :recordId
                AND Case_Type__c IN ('Metriport Cases', 'Portal Messages')
            ORDER BY CreatedDate DESC
            LIMIT :limitSize OFFSET :offsetSize
        ];
        for (Case c : cases) {
            // Determine the type based on Case_Type__c picklist value
            String caseType = (c.Case_Type__c == 'Portal Messages') ? 'PortalMessages' : 'MetriportCases';
            activities.add(new ActivityWrapper(
                c.Id,
                caseType,
                c.Subject,
                truncateWords(c.Description, 15),
                '',
                c.CreatedDate
            ));
        }
        
        // --- EVENTS ---
        List<Event> events = [
            SELECT Id, Subject, Location, ActivityDateTime, CreatedDate
            FROM Event
            WHERE WhatId = :recordId
            ORDER BY CreatedDate DESC
            LIMIT :limitSize OFFSET :offsetSize
        ];
        for (Event e : events) {
            activities.add(new ActivityWrapper(
                e.Id, 
                'Event', 
                e.Subject, 
                e.Location, 
                (e.ActivityDateTime != null ? String.valueOf(e.ActivityDateTime) : ''), 
                e.CreatedDate
            ));
        }

        for (Email_Log__c el : [
            SELECT Id,
                   Subject__c,
                   From_Email__c,
                   To_Email__c,
                   Received_Date_Time__c
            FROM Email_Log__c
            WHERE Account__c = :recordId
            ORDER BY Received_Date_Time__c DESC
            LIMIT :limitSize OFFSET :offsetSize
        ]) {
            activities.add(new ActivityWrapper(
                el.Id,
                'Email',
                el.Subject__c,
                el.From_Email__c,
                el.To_Email__c,
                el.Received_Date_Time__c
            ));
        }


        // --- CALL LOGS ---
        List<Task> calls = [
            SELECT Id, Subject, CallType, Status, CreatedDate
            FROM Task
            WHERE WhatId = :recordId  AND TaskSubtype = 'Call'
            ORDER BY CreatedDate DESC
            LIMIT :limitSize OFFSET :offsetSize
        ];
        for (Task ctask : calls) {
            activities.add(new ActivityWrapper(
                ctask.Id, 
                'Call', 
                ctask.Subject, 
                ctask.CallType, 
                ctask.Status, 
                ctask.CreatedDate
            ));
        }
        
        List<Message_Session__c> sessions = [
            SELECT Id,
                   Name,
                   Session_Status__c, Account__c,
                   CreatedDate
            FROM Message_Session__c
            WHERE Account__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
            OFFSET :offsetSize
        ];

        for (Message_Session__c ms : sessions) {
            activities.add(new ActivityWrapper(
                ms.Id,
                'MessagingSession',
                ms.Name,
                ms.Session_Status__c,
                '',
                ms.CreatedDate
            ));
        }

        // --- MESSAGE HISTORY (custom object) ---
        for (sra__Message_History__c mh : [
            SELECT Id, Name, sra__MessageSid__c, sra__Message_Body__c, CreatedDate, sra__Account__c
            FROM sra__Message_History__c
            WHERE sra__Account__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
        ]) {
            activities.add(new ActivityWrapper(
                mh.Id,
                'MessageHistory',
                mh.Name,
                '',
                mh.sra__Message_Body__c,
                mh.CreatedDate
            ));
        }

        // --- CALL HISTORY (custom object) ---
        String aiForwardingNumber = Label.Call_Forwarding_Number;
        for (ccra__Call_History__c ch : [
            SELECT Id, Name, ccra__Call_SID__c, CreatedDate, ccra__Call_Status__c, ccra__Account__c, ccra__Call_Forwarding_Number__c
            FROM ccra__Call_History__c
            WHERE ccra__Account__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
        ]) {
            String callType = (ch.ccra__Call_Forwarding_Number__c == aiForwardingNumber) ? 'AiCallHistory' : 'CallHistory';
            activities.add(new ActivityWrapper(
                ch.Id,
                callType,
                ch.Name,
                ch.ccra__Call_Status__c,
                '',
                ch.CreatedDate
            ));
        }

        // --- SENT FAX ---
        for (efaxapp__Sent_Fax__c sf : [
            SELECT Id, Name, efaxapp__Fax_Number__c, efaxapp__Status__c, CreatedDate
            FROM efaxapp__Sent_Fax__c
            WHERE efaxapp__Account__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT :limitSize OFFSET :offsetSize
        ]) {
            activities.add(new ActivityWrapper(
                sf.Id,
                'SentFax',
                sf.Name,
                sf.efaxapp__Fax_Number__c,
                sf.efaxapp__Status__c,
                sf.CreatedDate
            ));
        }

        // --- RECEIVED FAX ---
        for (efaxapp__Received_Fax__c rf : [
            SELECT Id, Name, efaxapp__Fax_Number__c, efaxapp__Status__c, CreatedDate
            FROM efaxapp__Received_Fax__c
            WHERE efaxapp__Account__c = :recordId
            ORDER BY CreatedDate DESC
            LIMIT :limitSize OFFSET :offsetSize
        ]) {
            activities.add(new ActivityWrapper(
                rf.Id,
                'ReceivedFax',
                rf.Name,
                rf.efaxapp__Fax_Number__c,
                rf.efaxapp__Status__c,
                rf.CreatedDate
            ));
        }

        // --- SORT ALL ACTIVITIES ---
        activities.sort();
        return activities;
    }
    
    public class ActivityWrapper implements Comparable {
        @AuraEnabled public Id recordId { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String field1 { get; set; }
        @AuraEnabled public String field2 { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String body { get; set; }
        
        public ActivityWrapper(Id recordId, String type, String title, String field1, String field2, Datetime createdDate) {
            this.recordId = recordId;
            this.type = type;
            this.title = title;
            this.field1 = field1;
            this.field2 = field2;
            this.body = field2;
            this.createdDate = createdDate;
        }
        
        public Integer compareTo(Object compareTo) {
            ActivityWrapper other = (ActivityWrapper) compareTo;
            if (this.createdDate == other.createdDate) return 0;
            return (this.createdDate > other.createdDate) ? -1 : 1;
        }
    }

    private static String truncateWords(String text, Integer maxWords) {
        if (String.isBlank(text)) return '';
        List<String> words = text.trim().split('\\s+');
        if (words.size() <= maxWords) return text.trim();
        List<String> truncated = new List<String>();
        for (Integer i = 0; i < maxWords; i++) {
            truncated.add(words[i]);
        }
        return String.join(truncated, ' ') + '...';
    }

    // Fallback: get parent account for Message History
    @AuraEnabled
    public static Id getParentAccountForMessage(Id changeRecordId) {
        if (changeRecordId == null) return null;
        sra__Message_History__c rec = [
            SELECT Id, sra__Account__c
            FROM sra__Message_History__c
            WHERE Id = :changeRecordId
            LIMIT 1
        ];
        return rec != null ? rec.sra__Account__c : null;
    }

    // Fallback: get parent account for Call History
    @AuraEnabled
    public static Id getParentAccountForCall(Id changeRecordId) {
        if (changeRecordId == null) return null;
        ccra__Call_History__c rec = [
            SELECT Id, ccra__Account__c
            FROM ccra__Call_History__c
            WHERE Id = :changeRecordId
            LIMIT 1
        ];
        return rec != null ? rec.ccra__Account__c : null;
    }
}