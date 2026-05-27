public class MetriportPayloadBatch implements Database.Batchable<String> {
    
    private String jsonPayload;
    
    // List of all resource types to process
    private static final List<String> RESOURCE_TYPES = new List<String>{
        'AllergyIntolerance',
        'Immunization',
        'Medication',
        'RelatedPerson',
        'FamilyMemberHistory',
        'Organization',
        'Encounter',
         'Condition',
        'Procedure',
        'Location',
        'Observation',
        'Practitioner',
        'DiagnosticReport',
        'CarePlan',
        'ServiceRequest',
        'Binary',
        'MetriportPatientDocument'
    };
    
    public MetriportPayloadBatch(String jsonPayload) {
        this.jsonPayload = jsonPayload;
    }
    
    // Start method - returns the list of resource types to process
    public Iterable<String> start(Database.BatchableContext bc) {
        System.debug('🚀 Batch started - will process ' + RESOURCE_TYPES.size() + ' resource types');
        return RESOURCE_TYPES;
    }
    
    // Execute method - processes ONE resource type at a time
    public void execute(Database.BatchableContext bc, List<String> scope) {
        // Scope will have 1 resource type (batch size = 1)
        for (String resourceType : scope) {
            try {
                queueJobForResourceType(resourceType, jsonPayload);
                System.debug('✅ Queued job for: ' + resourceType);
            } catch (Exception e) {
                System.debug('❌ Error queuing ' + resourceType + ': ' + e.getMessage());
            }
        }
    }
    
    // Finish method
    public void finish(Database.BatchableContext bc) {
        System.debug('✅ Batch processing complete - all resource types queued');
    }
    

    private void queueJobForResourceType(String resourceType, String jsonData) {
        switch on resourceType {
            when 'AllergyIntolerance' {
                System.enqueueJob(new AllergyJob(jsonData));
            }
            
            when 'Condition' {
                System.enqueueJob(new ConditionJob(jsonData));
            }

            when 'Procedure' {
                System.enqueueJob(new ProcedureJob(jsonData));
            }
            when 'Immunization' {
                System.enqueueJob(new ImmunizationJob(jsonData));
            }
            when 'Medication' {
                System.enqueueJob(new MedicationJob(jsonData));
            }        
            when 'RelatedPerson' {
                System.enqueueJob(new RelatedPersonJob(jsonData));
            }
            when 'FamilyMemberHistory' {
                System.enqueueJob(new FamilyHistoryJob(jsonData));
            }
            when 'Organization' {
                System.enqueueJob(new OrganizationJob(jsonData));
            }
            when 'Encounter' {
                System.enqueueJob(new EncounterJob(jsonData));
            }
            when 'Location' {
                System.enqueueJob(new LocationJob(jsonData));
            }
            when 'Observation' {
                System.enqueueJob(new ObservationJob(jsonData));
            }
            when 'Practitioner' {
                System.enqueueJob(new PractitionerJob(jsonData));
            }
            when 'DiagnosticReport' {
                System.enqueueJob(new DiagnosticJob(jsonData));
            }
            when 'CarePlan' {
                System.enqueueJob(new CarePlanJob(jsonData));
            }
            when 'ServiceRequest' {
                System.enqueueJob(new ServiceJob(jsonData));
            }
            when 'Binary' {
                System.enqueueJob(new SummaryJob(jsonData));
            }
            when 'MetriportPatientDocument' {
                System.enqueueJob(new MetriportPatientDocumentQueueable(jsonData));
            } 
            when else {
                System.debug('⚠️ Unknown resource type: ' + resourceType);
            }
        }
    }
}