public class MetriportDocumentParser {

    public static void processDocuments(String jsonResponse, String metriportPatientId) {

        if (String.isBlank(jsonResponse)) return;
        if (String.isBlank(metriportPatientId)) return;

        Id patientSfId;
        try {
            Account acc = [
                SELECT Id
                FROM Account
                WHERE Metriport_Patient_Id__c = :metriportPatientId
                LIMIT 1
            ];
            patientSfId = acc.Id;
        } catch (Exception e) {
            System.debug('Patient not found: ' + metriportPatientId);
            return;
        }

        if (patientSfId == null) return;

        Map<String, Object> rootMap;
        try {
            rootMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
        } catch (Exception e) {
            System.debug('JSON parse error: ' + e.getMessage());
            return;
        }

        if (rootMap == null || !rootMap.containsKey('documents')) return;

        List<Object> documents = (List<Object>) rootMap.get('documents');
        if (documents.isEmpty()) return;


        Set<String> metriportDocIds  = new Set<String>();
        Set<String> incomingFileNames = new Set<String>();

        for (Object dObj : documents) {
            Map<String, Object> docMap = (Map<String, Object>) dObj;
            String docId = (String) docMap.get('id');
            if (!String.isBlank(docId)) metriportDocIds.add(docId);

            String fileName = extractFileName(docMap);
            if (!String.isBlank(fileName)) incomingFileNames.add(fileName);
        }

        if (metriportDocIds.isEmpty()) return;


        Map<String, Document_Reference__c> existingDocs = new Map<String, Document_Reference__c>();
        for (Document_Reference__c dr : [
            SELECT Id, DocumentReferenceId__c
            FROM Document_Reference__c
            WHERE DocumentReferenceId__c IN :metriportDocIds
        ]) {
            existingDocs.put(dr.DocumentReferenceId__c, dr);
        }


        Set<String> existingFileNameKeys = new Set<String>();
        if (!incomingFileNames.isEmpty()) {
            for (Document_Reference__c dr : [
                SELECT File_Name__c
                FROM Document_Reference__c
                WHERE File_Name__c IN :incomingFileNames
                  AND Patient__c = :patientSfId
            ]) {
                if (!String.isBlank(dr.File_Name__c)) {
                    existingFileNameKeys.add(dr.File_Name__c.trim().toLowerCase());
                }
            }
        }

        /* -------------------------
           Build Records
        -------------------------- */
        List<Document_Reference__c> recordsToInsert = new List<Document_Reference__c>();
        Set<String> inFlightFileNameKeys = new Set<String>();

        for (Object dObj : documents) {
            Map<String, Object> docMap = (Map<String, Object>) dObj;

            String docId = (String) docMap.get('id');
            if (String.isBlank(docId)) continue;
            if (existingDocs.containsKey(docId)) continue;

            Document_Reference__c rec = new Document_Reference__c();
            rec.DocumentReferenceId__c = docId;
            rec.Patient__c             = patientSfId;
            rec.Status__c              = (String) docMap.get('status');
            rec.Description__c         = (String) docMap.get('description');

            String dateStr = (String) docMap.get('date');
            rec.Service_Date_Time__c   = parseDateTime(dateStr);
            System.debug('docId: ' + docId + ' date: ' + dateStr + ' => rec.Service_Date_Time__c: ' + rec.Service_Date_Time__c);

            if (docMap.containsKey('type')) {
                Map<String, Object> typeMap = (Map<String, Object>) docMap.get('type');
                if (typeMap.containsKey('coding')) {
                    List<Object> codings = (List<Object>) typeMap.get('coding');
                    if (!codings.isEmpty()) {
                        Map<String, Object> coding0 = (Map<String, Object>) codings[0];
                        rec.Name__c = (String) coding0.get('display');
                    }
                }
            }

            if (docMap.containsKey('meta')) {
                Map<String, Object> metaMap = (Map<String, Object>) docMap.get('meta');
                rec.File_Name__c = (String) metaMap.get('source');
            }

            if (docMap.containsKey('contained')) {
                List<Object> containedList = (List<Object>) docMap.get('contained');
                rec.Organization_Name__c = resolveOrganizationName(containedList);
            }


            String fileNameKey = String.isBlank(rec.File_Name__c) ? null : rec.File_Name__c.trim().toLowerCase();
            if (!String.isBlank(fileNameKey)) {
                if (existingFileNameKeys.contains(fileNameKey) || inFlightFileNameKeys.contains(fileNameKey)) {
                    System.debug('⏭️ Skipping Document_Reference__c (Duplicate File Name): ' + rec.File_Name__c);
                    continue;
                }
                inFlightFileNameKeys.add(fileNameKey);
            }

            recordsToInsert.add(rec);
        }

        if (recordsToInsert.isEmpty()) return;

        Database.SaveResult[] results = Database.insert(recordsToInsert, false);

        List<Error_Log__c> errorLogs = new List<Error_Log__c>();
        List<Id> docIds = new List<Id>();
        Integer successCount = 0;

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                successCount++;
                if (recordsToInsert[i].Id != null) docIds.add(recordsToInsert[i].Id);
            } else {
                List<String> errorMessages = new List<String>();
                for (Database.Error err : results[i].getErrors()) {
                    errorMessages.add(
                        'Status: ' + err.getStatusCode() +
                        ' | Message: ' + err.getMessage() +
                        ' | Fields: ' + String.join(err.getFields(), ', ')
                    );
                }
                Document_Reference__c failedDoc = recordsToInsert[i];
                errorLogs.add(new Error_Log__c(
                    Object_API_Name__c    = 'Document_Reference__c',
                    Error_Message__c      = String.join(errorMessages, '\n'),
                    Record_External_Id__c = failedDoc.DocumentReferenceId__c,
                    Context__c            = 'MetriportDocumentParser.processDocuments',
                    Stack_Trace__c        = 'Patient__c: ' + failedDoc.Patient__c +
                                            ' | DocumentReferenceId: ' + failedDoc.DocumentReferenceId__c
                ));
            }
        }

        if (!errorLogs.isEmpty()) {
            Database.insert(errorLogs, false);
            System.debug('⚠️ Failed Document_Reference__c inserts logged: ' + errorLogs.size());
        }

        System.debug('✅ Inserted Document_Reference__c records: ' + successCount +
                     ' | Failed: ' + (recordsToInsert.size() - successCount));

        if (!docIds.isEmpty()) {
            System.enqueueJob(new MetriportDocumentDownloadQueueable(docIds));
        }
    }

    /* -------------------------
       Helper: extract File_Name from meta.source
    -------------------------- */
    private static String extractFileName(Map<String, Object> docMap) {
        if (!docMap.containsKey('meta')) return null;
        Map<String, Object> metaMap = (Map<String, Object>) docMap.get('meta');
        return (String) metaMap.get('source');
    }

    /* -------------------------
       Date Parser
    -------------------------- */
    private static Datetime parseDateTime(String value) {
        if (String.isBlank(value)) return null;
        try {
            if (value.contains('T')) {
                String cleaned = value.trim().replace('Z', '');
                if (cleaned.contains('.')) cleaned = cleaned.substring(0, cleaned.indexOf('.'));
                cleaned = cleaned.replace('T', ' ');
                return Datetime.valueOfGmt(cleaned);
            } else {
                Date d = Date.valueOf(value);
                return Datetime.newInstanceGmt(d.year(), d.month(), d.day());
            }
        } catch (Exception e) {
            System.debug('DateTime parse error for value: ' + value + ' - ' + e.getMessage());
            return null;
        }
    }

    /* -------------------------
       Resolve Organization Name
    -------------------------- */
    private static String resolveOrganizationName(List<Object> containedList) {
        if (containedList == null) return null;
        for (Object cObj : containedList) {
            Map<String, Object> cMap = (Map<String, Object>) cObj;
            if (cMap != null &&
                'Organization'.equals(cMap.get('resourceType')) &&
                cMap.containsKey('name')) {
                return (String) cMap.get('name');
            }
        }
        return null;
    }
}