public class PatientAdmitHandler {

    public static void handle(Map<String, Object> payload) {
    try {
        System.debug('PatientAdmitHandler payload: ' + payload);

        Map<String, Object> innerPayload =
            (Map<String, Object>) payload.get('payload');

        if (innerPayload == null) {
            System.debug('PatientAdmitHandler: payload object is missing');
            return;
        }

        String fileUrl = (String) innerPayload.get('url');
         Map<String, Object> meta =
                (Map<String, Object>) payload.get('meta');
        
            String eventType = meta != null
                ? (String) meta.get('type')
                : null;
        System.debug('Event Type In Handler' +eventType);

        if (String.isBlank(fileUrl)) {
            System.debug('PatientAdmitHandler: URL is missing');
            return;
        }

        System.debug('Patient Admit JSON URL: ' + fileUrl);

        String admitJson = downloadJson(fileUrl);

        if (String.isBlank(admitJson)) {
            System.debug('PatientAdmitHandler: Failed to download JSON');
            return;
        }

        System.debug('Patient Admit JSON downloaded successfully');
        //System.debug('Patient Admit JSON ' + admitJson);
        if (!Test.isRunningTest()) {
         System.enqueueJob(new PatientAdmitJob(admitJson,eventType));
        }
         //System.debug('Patient Queue Runs Succ');
        //System.debug('Event Type In Handler 2' +eventType +admitjson);
        //System.enqueueJob(new MetriportADTNotificationServiceQueueable(admitJson, eventType));

        //MetriportADTNotificationService.sendADTNotification( admitJson, eventType);
         //System.debug('Patient ADT Below Debug');


    } catch (Exception e) {
        System.debug('PatientAdmitHandler Error: ' + e.getMessage());
    }
}


    private static String downloadJson(String fileUrl) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(fileUrl);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            return res.getBody();
        }

        System.debug(
            'Download failed: ' +
            res.getStatusCode() + ' ' +
            res.getBody()
        );
        return null;
    }
}