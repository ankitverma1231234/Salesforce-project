trigger CareObservationTrigger on CareObservation (after insert, after update, after Delete) {
    if(Trigger.isDelete &&Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'CareObservation',   
            'ObservationId__c',    
            'Account',                  
            'ObservedSubjectId'                  
        );  
    }

     if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
  
       CareObservationHandler.handleAfterInsert(Trigger.new);
        
    Map<Id, Account> accountsToUpdate = new Map<Id, Account>();
    for (CareObservation obs : Trigger.new) {
        if (obs.ObservedSubjectId == null || String.isBlank(obs.Value_Quantity__c)) {
            continue;
        }     
        String valueLower = obs.Value_Quantity__c.toLowerCase();       
        Decimal numericValue;
        try {
            String numberOnly = obs.Value_Quantity__c.replaceAll('[^0-9\\.]', '');
            numericValue = Decimal.valueOf(numberOnly);
        } catch (Exception e) {
            continue;
        }

        Account acc = accountsToUpdate.get(obs.ObservedSubjectId);
        if (acc == null) {
            acc = new Account(Id = obs.ObservedSubjectId);
        }

        // BODY WEIGHT
        if (obs.Name == 'Body weight') {

            // Convert ONLY if unit is kg
            if (valueLower.contains('kg')) {
                numericValue = numericValue * 2.20462; // kg → lb
            }
            // else assume already pounds

            acc.Weight_in_pounds__pc = numericValue.setScale(2);
        }

        // BODY HEIGHT
        else if (obs.Name == 'Body height') {

            // Convert ONLY if unit is cm
            if (valueLower.contains('cm')) {
                numericValue = numericValue * 0.393701; // cm → inches
            }
            // else assume already inches

            acc.Height_in_inches__pc = numericValue.setScale(2);
        }

        accountsToUpdate.put(acc.Id, acc);
    }

    if (!accountsToUpdate.isEmpty()) {
        update accountsToUpdate.values();
    }
    }
}