trigger ContentVersionGeminiTrigger on ContentVersion (after insert) {
   /*
    Set<Id> processedIds = new Set<Id>();

    for (ContentVersion cv : Trigger.new) {
        // Skip if this is not a new upload (e.g., version update handled separately)
        // Only process files with supported types
        if (cv.FileType == null) {
            continue;
        }

        String fileType = cv.FileType.toUpperCase();
        Set<String> supportedTypes = new Set<String>{
            'PDF', 'TXT', 'CSV', 'XML', 'HTML', 'JSON', 'RTF', 'LOG', 'MD', 'DOC', 'DOCX'
        };

        if (supportedTypes.contains(fileType) && !processedIds.contains(cv.Id)) {
            processedIds.add(cv.Id);
        }
    }

    // Enqueue one job per file (respecting Queueable limits)
    Integer jobCount = 0;
    for (Id cvId : processedIds) {
        if (jobCount < 50) { // Salesforce allows up to 50 queueable jobs per transaction
            System.enqueueJob(new GeminiFileSummaryQueueable(cvId));
            jobCount++;
        }
    }
        */
        
}