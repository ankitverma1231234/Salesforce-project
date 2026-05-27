public class MetriportfilterBatch implements Database.Batchable<String> {

    private String jsonPayload;

    // Only required resource types
    private static final List<String> RESOURCE_TYPES = new List<String>{
        'Medication',
        'MedicationAdministration',
        'MedicationRequest',
        'MedicationDispense',
        'MedicationStatement'
    };

    public MetriportfilterBatch(String jsonPayload) {
        this.jsonPayload = jsonPayload;
    }

    // Start
    public Iterable<String> start(Database.BatchableContext bc) {
        System.debug('🚀 Batch started - will process ' + RESOURCE_TYPES.size() + ' resource types');
        return RESOURCE_TYPES;
    }

    // Execute
    public void execute(Database.BatchableContext bc, List<String> scope) {
        for (String resourceType : scope) {
            try {
                queueJobForResourceType(resourceType, jsonPayload);
                System.debug('✅ Queued job for: ' + resourceType);
            } catch (Exception e) {
                System.debug('❌ Error queuing ' + resourceType + ': ' + e.getMessage());
            }
        }
    }

    // Finish
    public void finish(Database.BatchableContext bc) {
        System.debug('✅ Batch processing complete - all resource types queued');
    }

    // Same pattern as original class
    private void queueJobForResourceType(String resourceType, String jsonData) {
        switch on resourceType {



            when 'Medication' {
                System.enqueueJob(new MedicationJob(jsonData));
            }

            when 'MedicationAdministration' {
                System.enqueueJob(new MedicationAdministrationJob(jsonData));
            }

            when 'MedicationRequest' {
                System.enqueueJob(new MedicationRequestJob(jsonData));
            }

            when 'MedicationDispense' {
                System.enqueueJob(new MedicationDispenseJob(jsonData));
            }

            when 'MedicationStatement' {
                System.enqueueJob(new MedicationStatementJob(jsonData));
            }

            when else {
                System.debug('⚠️ Unknown resource type: ' + resourceType);
            }
        }
    }
}