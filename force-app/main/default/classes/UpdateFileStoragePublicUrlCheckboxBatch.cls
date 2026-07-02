public class UpdateFileStoragePublicUrlCheckboxBatch implements Database.Batchable<SObject> {

    // Query only records where the checkbox is currently false.
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, fra__File_Public_Url__c, Public_Url_Chekbox__c
            FROM fra__File_Storage__c
            WHERE Public_Url_Chekbox__c = false
        ]);
    }

    // Process each batch scope and update only records that have a public URL.
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<fra__File_Storage__c> recordsToUpdate = new List<fra__File_Storage__c>();

        for (SObject sobj : scope) {
            fra__File_Storage__c fileStorage = (fra__File_Storage__c) sobj;

            // Set checkbox only when the public URL has a value.
            if (!String.isBlank(fileStorage.fra__File_Public_Url__c)) {
                fileStorage.Public_Url_Chekbox__c = true;
                recordsToUpdate.add(fileStorage);
            }
        }

        // Bulk update only records that need changes.
        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

    // No post-processing required.
    public void finish(Database.BatchableContext bc) {
    }
}