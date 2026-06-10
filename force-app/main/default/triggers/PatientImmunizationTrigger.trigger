trigger PatientImmunizationTrigger on PatientImmunization (after insert, after update, after delete) {

    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.PatientImmunizationTrigger__c) {
        return;
    }

    if (Trigger.isAfter && Trigger.isDelete) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'PatientImmunization',
            'ImmunizationId__c',
            'Account',
            'PatientId'
        );
    }

    String objectType = 'PatientImmunization';

    if (Trigger.isDelete) {
        Set<Id> recordIds = new Set<Id>();
        for (PatientImmunization pi : Trigger.old) {
            recordIds.add(pi.Id);
        }

        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordIds, 'PatientImmunization');
        }

    } else {
        Set<Id> accountIds      = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>();
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';

        for (PatientImmunization pi : Trigger.new) {
            if (pi.PatientId != null) {
                accountIds.add(pi.PatientId);
                changedRecordIds.add(pi.Id);
            }
        }

        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(accountIds, operation, objectType, changedRecordIds);
        }
    }
}