public class MetriportDocumentParser {

    public static void processDocuments(String jsonResponse, String metriportPatientId) {

        if (String.isBlank(jsonResponse)) return;
        if (String.isBlank(metriportPatientId)) return;

        // -------------------------
        // Find Patient Account
        // -------------------------
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

        // -------------------------
        // Deserialize JSON
        // -------------------------
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

        // -------------------------
        // Collect Metriport IDs
        // -------------------------
        Set<String> metriportDocIds = new Set<String>();
        for (Object dObj : documents) {
            Map<String, Object> docMap = (Map<String, Object>) dObj;
            String docId = (String) docMap.get('id');
            if (!String.isBlank(docId)) metriportDocIds.add(docId);
        }

        if (metriportDocIds.isEmpty()) return;

        // -------------------------
        // Find Existing Records
        // -------------------------
        Map<String, Document_Reference__c> existingDocs = new Map<String, Document_Reference__c>();
        for (Document_Reference__c dr : [
            SELECT Id, DocumentReferenceId__c
            FROM Document_Reference__c
            WHERE DocumentReferenceId__c IN :metriportDocIds
        ]) {
            existingDocs.put(dr.DocumentReferenceId__c, dr);
        }

        // -------------------------
        // Build Records
        // -------------------------
        List<Document_Reference__c> recordsToInsert = new List<Document_Reference__c>();

        for (Object dObj : documents) {
            Map<String, Object> docMap = (Map<String, Object>) dObj;

            String docId = (String) docMap.get('id');
            if (String.isBlank(docId)) continue;
            if (existingDocs.containsKey(docId)) continue;

            Document_Reference__c rec = new Document_Reference__c();
            rec.DocumentReferenceId__c = docId;
            rec.Patient__c = patientSfId;
            rec.Status__c = (String) docMap.get('status');
            rec.Description__c = (String) docMap.get('description');

            // -------------------------
            // Parse Date
            // -------------------------
            String dateStr = (String) docMap.get('date');
            rec.Service_Date_Time__c = parseDateTime(dateStr);
            System.debug('docId: ' + docId + ' date: ' + dateStr + ' => rec.Date__c: ' + rec.Date__c);

            // -------------------------
            // Document Type Name
            // -------------------------
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

            // -------------------------
            // Meta
            // -------------------------
            if (docMap.containsKey('meta')) {
                Map<String, Object> metaMap = (Map<String, Object>) docMap.get('meta');
                rec.File_Name__c = (String) metaMap.get('source');
            }

            // -------------------------
            // Organization Name
            // -------------------------
            if (docMap.containsKey('contained')) {
                List<Object> containedList = (List<Object>) docMap.get('contained');
                rec.Organization_Name__c = resolveOrganizationName(containedList);
            }

            recordsToInsert.add(rec);
        }

        if (recordsToInsert.isEmpty()) return;

        insert recordsToInsert;

        // -------------------------
        // Queue Downloads
        // -------------------------
        List<Id> docIds = new List<Id>();
        for (Document_Reference__c d : recordsToInsert) {
            if (d.Id != null) docIds.add(d.Id);
        }

        if (!docIds.isEmpty()) {
            System.enqueueJob(new MetriportDocumentDownloadQueueable(docIds));
        }
    }

    // ==================================================
    // Date Parser (handles Date + ISO-8601 DateTime)
    // ==================================================
  private static Datetime parseDateTime(String value) {
    if (String.isBlank(value)) return null;

    try {
        // ISO 8601 format: 2015-11-24T00:00:00.000Z
        if (value.contains('T')) {

            String cleaned = value.trim();

            // Remove Z (UTC indicator)
            cleaned = cleaned.replace('Z', '');

            // Remove milliseconds if present
            if (cleaned.contains('.')) {
                cleaned = cleaned.substring(0, cleaned.indexOf('.'));
            }

            // Replace T with space (required by Apex)
            cleaned = cleaned.replace('T', ' ');

            return Datetime.valueOfGmt(cleaned);
        }
        else {
            // If only date provided, convert to midnight GMT
            Date d = Date.valueOf(value);
            return Datetime.newInstanceGmt(d.year(), d.month(), d.day());
        }

    } catch (Exception e) {
        System.debug('DateTime parse error for value: ' + value + ' - ' + e.getMessage());
        return null;
    }
}

    // ==================================================
    // Resolve Organization Name from contained list
    // ==================================================
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