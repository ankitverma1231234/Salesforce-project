public class MessageHistoryHandler {

    private static Boolean isRunning = false;

    public static void handleInboundMessages(List<sra__Message_History__c> newRecords) {

        System.debug(' MessageHistoryHandler started');

        if (isRunning) {
            System.debug('⚠ Recursion detected. Exiting handler.');
            return;
        }
        isRunning = true;

        /* ----------------------------------------------------
           1️⃣ Fetch Auto Reply Time Window (CMDT)
        ---------------------------------------------------- */
        Auto_Reply_Time_Window__mdt timeConfig = [
            SELECT Start_Hour__c, End_Hour__c
            FROM Auto_Reply_Time_Window__mdt
            LIMIT 1
        ];

        Integer startHour = Integer.valueOf(timeConfig.Start_Hour__c);
        Integer endHour   = Integer.valueOf(timeConfig.End_Hour__c);

        System.debug('⏰ Auto-reply time window → Start: ' + startHour + ', End: ' + endHour);

        /* ----------------------------------------------------
           2️⃣ Fetch Auto Reply Message Template
        ---------------------------------------------------- */
        List<sra__Message_Template__c> templateList = [
            SELECT sra__Template_Body__c
            FROM sra__Message_Template__c
            WHERE sra__Object_Name__c = 'sra__Message_History__c'
            AND Name = 'autoOutboundMessage'
            LIMIT 1
        ];

        if (templateList.isEmpty()) {
            System.debug(' No message template found. Exiting handler.');
            return;
        }

        String autoReplyMessage = templateList[0].sra__Template_Body__c;

        if (String.isBlank(autoReplyMessage)) {
            System.debug(' Template body is blank. Exiting handler.');
            return;
        }

        Set<Id> accountIds = new Set<Id>();

        for (sra__Message_History__c msg : newRecords) {
            
            if (msg.sra__Type__c == 'Inbound' && msg.sra__Account__c != null) {
                accountIds.add(msg.sra__Account__c);
                
            }
        }

        if (accountIds.isEmpty()) {
            return;
        }
        Map<Id, Integer> inboundCountMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT sra__Account__c acc, COUNT(Id) cnt
            FROM sra__Message_History__c
            WHERE sra__Account__c IN :accountIds
            AND sra__Type__c = 'Inbound'
            GROUP BY sra__Account__c
        ]) {
            inboundCountMap.put(
                (Id) ar.get('acc'),
                (Integer) ar.get('cnt')
            );

        }

        List<sra__Message_History__c> outboundMessages = new List<sra__Message_History__c>();

        for (sra__Message_History__c msg : newRecords) {

            if (msg.sra__Type__c != 'Inbound' || msg.sra__Account__c == null) {
                System.debug('⏭ Skipping non-inbound or account-less message.');
                continue;
            }

            Boolean isFirstInbound =
                inboundCountMap.get(msg.sra__Account__c) == 1;

            Integer hour = Integer.valueOf(
                msg.CreatedDate.format('H', UserInfo.getTimeZone().getID())
            );

            Boolean isOffHours =
                (startHour < endHour && hour >= startHour && hour < endHour) ||
                (startHour > endHour && (hour >= startHour || hour < endHour));



            if (isFirstInbound || isOffHours) {

                System.debug('📤 Creating auto-reply for Account: ' + msg.sra__Account__c);

                outboundMessages.add(new sra__Message_History__c(
                    sra__Account__c         = msg.sra__Account__c,
                    sra__Type__c            = 'Outbound',
                    sra__Sender_Number__c   = msg.sra__Receiver_Number__c,
                    sra__Receiver_Number__c = msg.sra__Sender_Number__c,
                    sra__Message_Body__c    = autoReplyMessage
                ));
            }
        }

        
        if (!outboundMessages.isEmpty()) {
           
            insert outboundMessages;
        } else {
            System.debug('ℹ No outbound messages to insert.');
        }

        System.debug(' MessageHistoryHandler completed');
    }
}