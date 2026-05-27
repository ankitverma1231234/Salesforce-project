@RestResource(urlMapping='/api/metriport/webhook/patient/*')
global class MetriportPatientWebhook {

    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String jsonBody = req.requestBody.toString();
            Map<String, Object> data =
                (Map<String, Object>) JSON.deserializeUntyped(jsonBody);

            String eventType = (String) data.get('metaType');
            System.debug('Patient Webhook Type: ' + eventType);

            if (String.isBlank(eventType)) {
                res.statusCode = 400;
                return;
            }

            if (eventType == 'patient.admit' ||
                eventType == 'patient.transfer' ||
                eventType == 'patient.discharge') {
				if (!Test.isRunningTest()) {
                System.enqueueJob(
                    new PatientAdmitJob(jsonBody, eventType)
                );
                }

            } else {
                System.debug('Ignoring event type: ' + eventType);
            }

            res.statusCode = 200;

        } catch (Exception e) {
            res.statusCode = 500;
        }
    }
}