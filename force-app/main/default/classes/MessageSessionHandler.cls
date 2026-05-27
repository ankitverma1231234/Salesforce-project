public Without Sharing class MessageSessionHandler {
    
    public static void handleInboundMessages(List<sra__Message_History__c> newMessages) {
        List<sra__Message_History__c> inboundMessages = new List<sra__Message_History__c>();
        Set<String> senderNumbers = new Set<String>();
        
        for (sra__Message_History__c msg : newMessages) {
            if (msg.sra__Type__c == 'Inbound' && String.isNotBlank(msg.sra__Sender_Number__c)) {
                inboundMessages.add(msg);
                senderNumbers.add(msg.sra__Sender_Number__c);
            }
        }
        
        if (inboundMessages.isEmpty()) {
            return;
        }
        
        MessageCustomization__c customSetting = MessageCustomization__c.getInstance('Message');
        
        if (customSetting == null || customSetting.Session_Time__c == null) {
            System.debug(LoggingLevel.ERROR, 'Session_Time__c not configured in MessageCustomization__c');
            return; 
        }
        
        Decimal sessionHours = customSetting.Session_Time__c;
        Map<String, Message_Session__c> activeSessionMap = getActiveSessionMap(senderNumbers);
        
        List<Message_Session__c> sessionsToUpdate = new List<Message_Session__c>();
        List<Message_Session__c> sessionsToInsert = new List<Message_Session__c>();
        List<Message_Session__c> sessionsToClose = new List<Message_Session__c>();
        Map<Id, Id> messageIdToSessionIdMap = new Map<Id, Id>(); 
        Set<Id> processedSessionIds = new Set<Id>();
        
        for (sra__Message_History__c msg : inboundMessages) {
            DateTime messageTime = msg.CreatedDate;
            Message_Session__c existingSession = activeSessionMap.get(msg.sra__Sender_Number__c);
            system.debug('check the class call');
            if (existingSession != null) {
                if (isWithinSessionWindow(messageTime, existingSession.End_Time__c)) {
                    handleSessionExtension(
                        existingSession, 
                        messageTime, 
                        sessionHours, 
                        sessionsToUpdate, 
                        processedSessionIds
                    );
                    messageIdToSessionIdMap.put(msg.Id, existingSession.Id);
                } else {
                    Message_Session__c newSession = handleSessionTransition(
                        existingSession,
                        msg.sra__Sender_Number__c,
                        messageTime,
                        sessionHours,
                        msg.OwnerId,
                        msg.sra__Account__c,
                        sessionsToClose,
                        sessionsToInsert,
                        activeSessionMap
                    );
                    messageIdToSessionIdMap.put(msg.Id, null);
                }
            } else {
                Message_Session__c newSession = createNewSession(
                    msg.sra__Sender_Number__c, 
                    messageTime, 
                    sessionHours,
                    msg.OwnerId,
                    msg.sra__Account__c
                );
                sessionsToInsert.add(newSession);
                activeSessionMap.put(msg.sra__Sender_Number__c, newSession);
                messageIdToSessionIdMap.put(msg.Id, null); 
            }
        }
        
        performDMLOperations(sessionsToClose, sessionsToUpdate, sessionsToInsert);
        
        // Now link messages to their sessions
        List<sra__Message_History__c> messagesToUpdate = new List<sra__Message_History__c>();
        
        for (sra__Message_History__c msg : inboundMessages) {
            Id sessionId = messageIdToSessionIdMap.get(msg.Id);
            if (sessionId == null) {
                Message_Session__c session = activeSessionMap.get(msg.sra__Sender_Number__c);
                if (session != null && session.Id != null) {
                    sessionId = session.Id;
                }
            }
            if (sessionId != null) {
                messagesToUpdate.add(new sra__Message_History__c(
                    Id = msg.Id,
                    Message_Session__c = sessionId
                ));
            }
        }
        
        if (!messagesToUpdate.isEmpty()) {
            try {
                update messagesToUpdate;
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, 'Error linking messages to sessions: ' + e.getMessage());
            }
        }
        
        if (!sessionsToInsert.isEmpty()) {
            AutoReplyHelper.sendAutoReplyForNewSessions(sessionsToInsert);
        }
    }
    
    private static Map<String, Message_Session__c> getActiveSessionMap(Set<String> phoneNumbers) {
        Map<String, Message_Session__c> sessionMap = new Map<String, Message_Session__c>();
        
        for (Message_Session__c session : [
            SELECT Id, Phone_Number__c, Start_Time__c, End_Time__c, Session_Status__c, Account__c
            FROM Message_Session__c
            WHERE Phone_Number__c IN :phoneNumbers
            AND Session_Status__c = 'Open'
            ORDER BY Start_Time__c DESC]) {
                if (!sessionMap.containsKey(session.Phone_Number__c)) {
                    sessionMap.put(session.Phone_Number__c, session);
                }
            }
        
        return sessionMap;
    }
   
    private static Boolean isWithinSessionWindow(DateTime messageTime, DateTime sessionEndTime) {
        return messageTime <= sessionEndTime;
    }
    
    // Helper method to handle session extension
    private static void handleSessionExtension(
        Message_Session__c session,
        DateTime messageTime,
        Decimal sessionHours,
        List<Message_Session__c> sessionsToUpdate,
        Set<Id> processedSessionIds
    ) {
        Integer sessionMinutes = (Integer)(sessionHours * 60);
        DateTime newEndTime = messageTime.addMinutes(sessionMinutes);
        
        if (!processedSessionIds.contains(session.Id)) {
            session.End_Time__c = newEndTime;
            sessionsToUpdate.add(session);
            processedSessionIds.add(session.Id);
        } else if (newEndTime > session.End_Time__c) {
            session.End_Time__c = newEndTime;
        }
    }
   
    private static Message_Session__c handleSessionTransition(
        Message_Session__c oldSession,
        String phoneNumber,
        DateTime messageTime,
        Decimal sessionHours,  
        Id ownerId,
        Id accountId,                                      
        List<Message_Session__c> sessionsToClose,
        List<Message_Session__c> sessionsToInsert,
        Map<String, Message_Session__c> activeSessionMap
    ) {
        // Close old session
        sessionsToClose.add(new Message_Session__c(
            Id = oldSession.Id,
            Session_Status__c = 'Closed'
        ));
        
        Message_Session__c newSession = createNewSession(
            phoneNumber,
            messageTime,
            sessionHours,  
            ownerId,
            accountId              
        );
        sessionsToInsert.add(newSession);
        activeSessionMap.put(phoneNumber, newSession);
        
        return newSession;
    }
    private static Message_Session__c createNewSession(
    String phoneNumber, 
    DateTime startTime, 
    Decimal sessionHours,  
    Id ownerId,
    Id accountId                                       
) {
    Integer sessionMinutes = (Integer)(sessionHours * 60);
    Message_Session__c newSession = new Message_Session__c(
        Phone_Number__c = phoneNumber,
        Start_Time__c = startTime,
        End_Time__c = startTime.addMinutes(sessionMinutes),
        Session_Status__c = 'Open'
    );
    
    if (ownerId != null) {
        newSession.OwnerId = ownerId;
    }

    if (accountId != null) {            
        newSession.Account__c = accountId;
    } else if (String.isNotBlank(phoneNumber)) {
        // Dynamically fetch all Phone-type fields from the Account object
        Map<String, Schema.SObjectField> accountFieldMap = Schema.SObjectType.Account.fields.getMap();
        List<String> phoneFields = new List<String>();

        for (String fieldName : accountFieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = accountFieldMap.get(fieldName).getDescribe();
            if (fieldDescribe.getType() == Schema.DisplayType.PHONE) {
                phoneFields.add(fieldName);
            }
        }

        if (!phoneFields.isEmpty()) {
            // Build a dynamic SOQL query with OR conditions for all phone fields
            List<String> whereConditions = new List<String>();
            for (String phoneField : phoneFields) {
                whereConditions.add(phoneField + ' = :phoneNumber');
            }

            String query = 'SELECT Id FROM Account WHERE ' 
                         + String.join(whereConditions, ' OR ') 
                         + ' LIMIT 1';

            List<Account> matchedAccounts = Database.query(query);

            if (!matchedAccounts.isEmpty()) {
                newSession.Account__c = matchedAccounts[0].Id;
            }
        }
    }
    
    return newSession;
}
    
    // Helper method to perform DML operations
    private static void performDMLOperations(
        List<Message_Session__c> sessionsToClose,
        List<Message_Session__c> sessionsToUpdate,
        List<Message_Session__c> sessionsToInsert
    ) {
        // Close sessions first to avoid conflicts
        if (!sessionsToClose.isEmpty()) {
            try {
                update sessionsToClose;
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, 'Error closing sessions: ' + e.getMessage());
            }
        }
        

        if (!sessionsToUpdate.isEmpty()) {
            try {
                update sessionsToUpdate;
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, 'Error updating sessions: ' + e.getMessage());
            }
        }
       
        if (!sessionsToInsert.isEmpty()) {
            try {
                insert sessionsToInsert;
            } catch (DmlException e) {
                System.debug('Error inserting sessions: ' + e.getMessage());
            }
        }
    }
   
    public static void linkOutboundMessagesToSessions(List<sra__Message_History__c> outboundMessages) {
        Set<String> receiverNumbers = new Set<String>();
        List<sra__Message_History__c> messagesToLink = new List<sra__Message_History__c>();
        
        for (sra__Message_History__c msg : outboundMessages) {
            if (msg.sra__Type__c == 'Outbound' && String.isNotBlank(msg.sra__Receiver_Number__c)) {
                receiverNumbers.add(msg.sra__Receiver_Number__c);
                messagesToLink.add(msg);
            }
        }
        
        if (receiverNumbers.isEmpty()) {
            return;
        }
        
        Map<String, Message_Session__c> activeSessionMap = getActiveSessionMap(receiverNumbers);
        List<sra__Message_History__c> messagesToUpdate = new List<sra__Message_History__c>();
        
        for (sra__Message_History__c msg : messagesToLink) {
            Message_Session__c session = activeSessionMap.get(msg.sra__Receiver_Number__c);
            if (session != null) {
                messagesToUpdate.add(new sra__Message_History__c(
                    Id = msg.Id,
                    Message_Session__c = session.Id
                ));
            }
        }
        if (!messagesToUpdate.isEmpty()) {
            try {
                update messagesToUpdate;
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, 'Error linking outbound messages to sessions: ' + e.getMessage());
            }
        }
    }
}