trigger CDSyncTrigger on ContentDocument (after insert, after delete) {

    List<Content_Document_Event__e> events = new List<Content_Document_Event__e>();

    // -------- AFTER INSERT --------
    if (Trigger.isAfter && Trigger.isInsert) {
        for (ContentDocument cd : Trigger.new) {
            if (cd.Id != null) {
                events.add(new Content_Document_Event__e(
                    ContentDocumentId__c = cd.Id
                ));
            }
        }
    }
    
    Set<id> recordDeletedids = New Set<id>();
    // -------- AFTER DELETE --------
    if (Trigger.isAfter && Trigger.isDelete) {
        for (ContentDocument cd : Trigger.old) {
                recordDeletedids.add(cd.id);
            
        }
    }
    
    if(!recordDeletedids.isEmpty()){
        MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordDeletedids, 'ContentDocument');
    }

    // -------- PUBLISH EVENTS --------
    if (!events.isEmpty()) {
        EventBus.publish(events);
    }
}