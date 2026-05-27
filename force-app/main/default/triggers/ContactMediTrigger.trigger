trigger ContactMediTrigger on Contact (after insert, after update, after delete) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.ContactMediTrigger__c) {
        return;
    }
        String objectType = 'Contact';        
        if(Trigger.isDelete &&Trigger.isAfter) {
            RecordAuditLogHandler.logDeletedRecords(
                Trigger.old,
                'Contact',   
                'RelatedPersonId__c',    
                'Account',                  
                'Account__c'                  
            );          
            Set<Id> recordIds = new Set<Id>();
            
            for (Contact con : Trigger.old) {
                recordIds.add(con.Id);
            }            
            if (!recordIds.isEmpty()) {
                MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordIds, 'Contact');
            }
        } else {
            Set<Id> accountIds = new Set<Id>();
            Set<Id> changedRecordIds = new Set<Id>(); 
            String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';
            
            for (Contact con : Trigger.new) {
                if (con.Account__c != null) {
                    accountIds.add(con.Account__c);
                    changedRecordIds.add(con.Id); 
                }
            }            
            if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
                MedicalSalesforceRecord.sendPatientDataToThirdParty(accountIds, operation, objectType, changedRecordIds);
            }
        }
    }