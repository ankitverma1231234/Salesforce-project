@RestResource(urlMapping='/metriportWebhook/*')
global with sharing class MetriportWebhookHandler {

    @HttpPost
    global static void handleWebhook() {
        try {

            String requestBody = RestContext.request.requestBody.toString();
            System.debug('Received Webhook Body: ' + requestBody);
            
            Map<String, String> headers = RestContext.request.headers;
            String signature = headers.get('x-metriport-signature');
            System.debug('Webhook Signature Header: ' + signature);



           // Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(requestBody);


            //System.debug(payload);
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            system.debug('Json Full URL' +requestBody);
			System.debug('json' + data);
            
            Map<String, Object> meta =
                (Map<String, Object>) data.get('meta');

            String eventType = meta != null
                ? (String) meta.get('type')
                : null;
            
            System.debug('Webhook Type: ' + eventType);
            if(eventType != null){
            if (eventType == 'patient.admit' || eventType == 'patient.transfer' || eventType == 'patient.discharge' ){
              PatientAdmitHandler.handle(data);  
                
            } 
            }

        List<Object> patients = (List<Object>) data.get('patients');
        if (patients != null && !patients.isEmpty()) {

            Map<String, Object> patient = (Map<String, Object>) patients[0];
            Map<String, Object> bundle = (Map<String, Object>) patient.get('bundle');

            List<Object> entries = (List<Object>) bundle.get('entry');
            Map<String, Object> entry0 = (Map<String, Object>) entries[0];

            Map<String, Object> resource = (Map<String, Object>) entry0.get('resource');
            List<Object> contents = (List<Object>) resource.get('content');

            Map<String, Object> contentObj = (Map<String, Object>) contents[0];
            Map<String, Object> attachment = (Map<String, Object>) contentObj.get('attachment');

            String fileUrl = (String) attachment.get('url');

            System.debug('S3 JSON URL: ' + fileUrl);

            String patientJson = fetchMetriportJson(fileUrl);

            System.debug('Full Patient JSON: ' + patientJson);
            
            //FhirParser.parseAll(patientJson);
           // AllergyIntoleranceHandler.parseAndInsertAllergies(patientJson);
            //ImmunizationHandler.parseAndInsertImmunizations(patientJson);
            //fhirObjectMappingHandler.parseAndInsertMedications(patientJson);
            //MedicationHandler.parseAndInsertMedicationDispenses(patientJson);
            //MedicationHandler.parseAndInsertMedicationRequests(patientJson);
           //fhirObjectMappingHandler.parseAndInsertMedicationRequests(patientJson);
            // fhirObjectMappingHandler.parseAndInsertMedicationAdministrations(patientJson);
            //fhirObjectMappingHandler.parseAndInsertConditions(patientJson);
            // fhirObjectMappingHandler.parseAndInsertMedicationStatements(patientJson);
           // fhirObjectMappingHandler.parseAndInsertProcedures(patientJson);
             //fhirObjectMappingHandler.parseAndInsertCoverages(patientJson);
             //fhirObjectMapping.parseAndInsertEncounters(patientJson);
           // fhirObjectMapping.parseAndInsertOrganizations(patientJson);
            //fhirObjectMapping.parseAndInsertLocations(patientJson);
           // fhirObjectMapping.parseAndInsertPractitioners(patientJson);
            //fhirObjectMapping.parseAndInsertObservations(patientJson);
            //fhirObjectMapping.parseAndInsertDiagnosticReports(patientJson);
            //fhirObjectMapping.parseAndInsertCarePlans(patientJson);
            // fhirObjectMapping.parseAndInsertRelatedPersons(patientJson);
            //fhirObjectMapping.parseAndInsertServiceRequests(patientJson);
             //fhirObjectMapping.parseBinaryAndUpdateAccount(patientJson);
             //fhirObjectMapping.parseAndInsertFamilyMemberHistory(patientJson);
            
            //Before Encounters Needed to Insert the Location
           // System.enqueueJob(new PractitionerJob(patientJson));
            //System.enqueueJob(new MedicationDispenseJob(patientJson));

            
           System.enqueueJob(new MetriportPatientDocumentQueueable(patientJson));
            
            

        }
        } 
        catch (Exception e) {
            System.debug('Error in webhook: ' + e.getMessage());
            RestContext.response.statusCode = 500;
        }
    }
    
    public static String fetchMetriportJson(String fileUrl) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(fileUrl);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            return res.getBody();
        }
        System.debug('Download failed: ' + res.getStatus() + ' ' + res.getBody());
        return null;
    }
}