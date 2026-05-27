public without sharing class MetriportADTNotificationServiceQueueable implements Queueable {

    private String bundleJson;
    private String eventType;

    // Constructor to pass the parameters
    public MetriportADTNotificationServiceQueueable(String bundleJson, String eventType) {
        this.bundleJson = bundleJson;
        this.eventType = eventType;
    }

    public void execute(QueueableContext context) {

        // Validation
        if (String.isBlank(bundleJson) || String.isBlank(eventType)) {
            System.debug('Queueable: Invalid input, exiting.');
            return;
        }

        // Deserialize JSON
        Map<String, Object> bundle;
        try {
            bundle = (Map<String, Object>) JSON.deserializeUntyped(bundleJson);
        } catch (Exception e) {
            System.debug('Queueable: Failed to deserialize JSON: ' + e.getMessage());
            return;
        }

        List<Object> entries = (List<Object>) bundle.get('entry');
        if (entries == null || entries.isEmpty()) {
            System.debug('Queueable: No entries in JSON, exiting.');
            return;
        }

        String patientId;
        String encounterId;
        
        for (Object obj : entries) {
            Map<String, Object> entry = (Map<String, Object>) obj;
            Map<String, Object> resource = (Map<String, Object>) entry.get('resource');
            if (resource == null) continue;
        
            String resourceType = (String) resource.get('resourceType');
            String resId = (String) resource.get('id');
        
            System.debug('ResourceType: ' + resourceType + ', ResourceId: ' + resId);
        
            if (resourceType == 'Patient' && patientId == null) {
                patientId = resId;
            } else if (resourceType == 'Encounter' && encounterId == null) {
                encounterId = resId;
            }
        }
        System.debug('Extracted PatientId: ' + patientId + ', EncounterId: ' + encounterId);


        // Retrieve Account
        Account acc;
        try {
            acc = [
                SELECT Id, Name, OwnerId
                FROM Account
                WHERE Metriport_Patient_id__c = :patientId
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Queueable: Failed to retrieve Account: ' + e.getMessage());
            return;
        }

        // Retrieve Visit
        // 
        System.debug('Visit Id See'+ encounterId);
        Visit visit;
        try {
            visit = [
                SELECT Id, Name, VisitId__c, Status,Place.Name,Transfer_Location__r.Name,ADT_Notify__c
                FROM Visit
                WHERE VisitId__c = :encounterId
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Queueable: Failed to retrieve Visit: ' + e.getMessage());
            return;
        }

        // Get Custom Notification Type
        Id notificationTypeId;
        try {
            notificationTypeId = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = 'Metriport_ADT_Notify'
                LIMIT 1
            ].Id;
        } catch (Exception e) {
            System.debug('Queueable: Failed to get CustomNotificationType: ' + e.getMessage());
            return;
        }
        String event;
        String locationPart;

        if (eventType == 'patient.admit') {
            event = 'Admit';
            locationPart = 'to ' + visit.Place.Name;
        } else if (eventType == 'patient.transfer') {
            event = 'Transferred';
            locationPart = 'to ' + visit.Transfer_Location__r.Name;
        } else if (eventType == 'patient.discharge') {
            event = 'Discharge';
            locationPart = 'from ' + visit.Place.Name;
        } else {
            event = eventType;
            locationPart = ''; // fallback if unknown
        }
        
        // Build the notification body dynamically
        String body = 'Patient ' + acc.Name +
                      ' is ' + event + ' ' + locationPart +
                      ' and the Encounter is ' + visit.Name;

        // Build and send notification
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(notificationTypeId);
        notification.setTitle('Metriport ADT Event');
        notification.setTargetId(acc.Id);
        notification.setBody(body);

        Set<String> recipients = new Set<String>();
        recipients.add(acc.OwnerId);

        try {
            notification.send(recipients);
            System.debug('Queueable: Notification sent successfully to ' + acc.OwnerId);
               if (!visit.ADT_Notify__c) {
        visit.ADT_Notify__c = true;
        update visit;
    }
        } catch (Exception e) { 
            System.debug('Queueable: Failed to send notification: ' + e.getMessage());
        }
    }
}