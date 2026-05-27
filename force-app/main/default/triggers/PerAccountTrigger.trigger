trigger PerAccountTrigger on Account (after insert) {
    Set<Id> contactIds = new Set<Id>();
    
    for (Account acc : Trigger.new) {
        // Only Person Accounts
        if (!acc.IsPersonAccount) {
            continue;
        }
        
        if (Trigger.isInsert && 
            acc.PersonContactId != null &&
            acc.PersonEmail != null &&
            acc.PersonMobilePhone != null
        ) {
            contactIds.add(acc.PersonContactId);
        }
    }
    
    if (!contactIds.isEmpty()) {
        for (Id contactId : contactIds) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(contactId, 'INSERT');
        }
    }
}