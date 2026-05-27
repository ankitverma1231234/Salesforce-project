trigger MedicationTrigger on Medication ( after insert, after update, after delete) {
    
    if(Trigger.isDelete &&Trigger.isAfter) {
        //logic for delete log record 
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'Medication',   
            'MedicationId__c',    
            'Account',                  
            'Patient__c'                  
        );    
    }
     /*
    String objectType = 'Medication';
    if (Trigger.isAfter && Trigger.isDelete) {

        Set<Id> recordIds = new Set<Id>();

        for (Medication med : Trigger.old) {
            recordIds.add(med.Id);
        }

        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(
                recordIds,
                objectType
            );
        }

    } else {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>();
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';

        for (Medication med : Trigger.new) {
            if (med.Patient__c != null) {
                accountIds.add(med.Patient__c);
                changedRecordIds.add(med.Id);
            }
        }

        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(
                accountIds,
                operation,
                objectType,
                changedRecordIds
            );
        }
    }
*/
}