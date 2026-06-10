public class DelayedFileSyncQueueable implements Queueable {

    private List<Map<String, Object>> fileResults;

    public DelayedFileSyncQueueable(List<Map<String, Object>> fileResults) {
        this.fileResults = fileResults;
    }

    public void execute(QueueableContext qc) {

        System.debug('DEBUG: Starting DelayedFileSyncQueueable');
        System.debug('DEBUG: Incoming fileResults size = ' + 
            (fileResults == null ? 0 : fileResults.size()));

        List<Id> contentVersionIds = new List<Id>();

        for (Map<String, Object> r : fileResults) {

            Boolean success = (Boolean) r.get('success');
            String message = (String) r.get('message');
            String id = (String) r.get('id');

            System.debug('DEBUG: Processing result => success=' + success +
                         ', message=' + message +
                         ', id=' + id);

            if (success == true &&
                message == 'File created' &&
                id != null) {

                contentVersionIds.add((Id) id);
            }
        }

        System.debug('DEBUG: Valid ContentVersion IDs = ' + contentVersionIds);

        if (contentVersionIds.isEmpty()) {
            System.debug('DEBUG: No valid ContentVersion IDs found. Exiting.');
            return;
        }

        List<ContentVersion> versions = [
            SELECT ContentDocumentId, FirstPublishLocationId
            FROM ContentVersion
            WHERE Id IN :contentVersionIds
            AND ContentDocumentId != null
        ];

        System.debug('DEBUG: ContentVersion records found = ' + versions.size());

        Set<Id> docIds = new Set<Id>();

        for (ContentVersion cv : versions) {
            System.debug('DEBUG: ContentVersion => Id=' + cv.Id +
                         ', ContentDocumentId=' + cv.ContentDocumentId +
                         ', FirstPublishLocationId=' + cv.FirstPublishLocationId);

            docIds.add(cv.ContentDocumentId);
        }

        System.debug('DEBUG: Extracted ContentDocumentIds = ' + docIds);

        if (docIds.isEmpty()) {
            System.debug('DEBUG: No ContentDocumentIds found. Exiting.');
            return;
        }

        Set<Id> finalDocs = new Set<Id>();

        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :docIds
        ]) {

            System.debug('DEBUG: Found ContentDocumentLink => ContentDocumentId=' +
                         link.ContentDocumentId +
                         ', LinkedEntityId=' + link.LinkedEntityId);

            finalDocs.add(link.ContentDocumentId);
        }

        System.debug('DEBUG: Final valid documents for sync = ' + finalDocs);

        if (finalDocs.isEmpty()) {
            System.debug('DEBUG: No ContentDocumentLinks found. Sync aborted.');
            return;
        }

        System.debug('DEBUG: About to call external sync service with ' +
                     finalDocs.size() + ' documents');

        AccountFileExternalSyncService.SyncResult syncResult =
            AccountFileExternalSyncService.queueContentDocumentSync(
                new List<Id>(finalDocs)
            );

        System.debug('DEBUG: Sync Job Created = ' + syncResult.jobId);
        System.debug('DEBUG: Sync Failed = ' + syncResult.failed);
        System.debug('DEBUG: Sync Error Message = ' + syncResult.errorMessage);
    }
}