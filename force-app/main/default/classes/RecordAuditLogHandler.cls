public class RecordAuditLogHandler {    

    public static void logDeletedRecords(
        List<SObject> deletedRecords,
        String objectAPIName,
        String externalIdFieldName,
        String parentObjectAPIName,
        String parentIdFieldName
    ) {

        System.debug('=== RecordAuditLogHandler START ===');
        System.debug('Object API Name: ' + objectAPIName);
        System.debug('External Id Field: ' + externalIdFieldName);
        System.debug('Parent Object API Name: ' + parentObjectAPIName);
        System.debug('Parent Id Field: ' + parentIdFieldName);
        System.debug('Total Records Received: ' + deletedRecords.size());

        List<Deleted_Record_Audit__c> auditLogs = new List<Deleted_Record_Audit__c>();

        for (SObject record : deletedRecords) {

            System.debug('Processing Record Id: ' + record.get('Id'));

            Deleted_Record_Audit__c log = new Deleted_Record_Audit__c();

            log.Object_API_Name__c = objectAPIName;
            log.Deleted_Record_Id__c = String.valueOf(record.get('Id'));

            if (externalIdFieldName != null && record.get(externalIdFieldName) != null) {
                log.External_Id_Metriport__c = String.valueOf(record.get(externalIdFieldName));
                System.debug('External Id Value: ' + log.External_Id_Metriport__c);
            }

            if (parentIdFieldName != null && record.get(parentIdFieldName) != null) {
                log.Parent_Record_Id__c = String.valueOf(record.get(parentIdFieldName));
                log.Parent_Object_API_Name__c = parentObjectAPIName;

                System.debug('Parent Record Id: ' + log.Parent_Record_Id__c);
                System.debug('Parent Object API Name: ' + parentObjectAPIName);
            }

            System.debug('Audit Log Prepared: ' + log);

            auditLogs.add(log);
        }

        System.debug('Total Audit Logs to Insert: ' + auditLogs.size());

        if (!auditLogs.isEmpty()) {
            try {
                insert auditLogs;
                System.debug('Audit Logs Inserted Successfully');
            } catch (Exception e) {
                System.debug('RecordAuditLogHandler Error: ' + e.getMessage());
            }
        }

        System.debug('=== RecordAuditLogHandler END ===');
    }
}