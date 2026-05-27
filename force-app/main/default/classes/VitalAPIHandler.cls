public class VitalAPIHandler {
    
    private static final Map<String, String> VITAL_NAME_MAP = new Map<String, String>{
            'systolic blood pressure'                                          => 'systolic_blood_pressure',
            'respiratory rate'                                                 => 'respiratory_rate',
            'oxygen saturation in arterial blood by pulse oximetry'            => 'oxygen_saturation',
            'heart rate'                                                       => 'heart_rate',
            'diastolic blood pressure'                                         => 'diastolic_blood_pressure',
            'body weight'                                                      => 'body_weight',
            'body temperature'                                                 => 'body_temperature',
            'body mass index (bmi) [ratio]'                                    => 'bmi',
            'body height'                                                      => 'body_height'
            
            };
                
                @future(callout=true)
                public static void sendData(Set<Id> recIds) {
                    BatonPortalAPI__c cs = BatonPortalAPI__c.getInstance();
                    if (cs == null || String.isBlank(cs.Vitals_API__c)) {
                        System.debug(LoggingLevel.WARN, 'VitalAPIHandler: Custom setting missing or API URL blank.');
                        return;
                    }
                    
                    List<CareObservation> records = [
                        SELECT Id, Name, Value_Quantity__c, ObservedSubjectId, CreatedDate, LastModifiedDate
                        FROM CareObservation
                        WHERE Id IN :recIds AND ObservedSubjectId != null
                    ];
                    if (records.isEmpty()) return;
                    
                    
                    List<CareObservation> allowedRecords = new List<CareObservation>();
                    for (CareObservation rec : records) {
                        String nameLower = rec.Name != null ? rec.Name.toLowerCase() : null;
                        if (nameLower != null && VITAL_NAME_MAP.containsKey(nameLower)) {
                            allowedRecords.add(rec);
                        }
                    }
                    if (allowedRecords.isEmpty()) return;
                    
                    Map<String, CareObservation> latestByName = new Map<String, CareObservation>();
                    Map<String, Integer> countByName         = new Map<String, Integer>();
                    
                    for (CareObservation rec : allowedRecords) {
                        String key = rec.Name.toLowerCase();
                        countByName.put(key, (countByName.containsKey(key) ? countByName.get(key) : 0) + 1);
                        
                        if (!latestByName.containsKey(key) ||
                            rec.CreatedDate > latestByName.get(key).CreatedDate) {
                                latestByName.put(key, rec);
                            }
                    }
                    
                    List<CareObservation> toSend = new List<CareObservation>();
                    Set<Id> addedIds = new Set<Id>();
                    
                    for (CareObservation rec : allowedRecords) {
                        String key = rec.Name.toLowerCase();
                        Integer cnt = countByName.get(key);
                        
                        if (cnt > 1) {
                            CareObservation latest = latestByName.get(key);
                            if (!addedIds.contains(latest.Id)) {
                                toSend.add(latest);
                                addedIds.add(latest.Id);
                            }
                        } else {
                            if (!addedIds.contains(rec.Id)) {
                                toSend.add(rec);
                                addedIds.add(rec.Id);
                            }
                        }
                    }
                    
                    Set<Id> accIds = new Set<Id>();
                    for (CareObservation rec : toSend)
                        accIds.add(rec.ObservedSubjectId);
                    
                    Map<Id, Account> accMap = new Map<Id, Account>(
                        [SELECT Id, PersonContactId FROM Account WHERE Id IN :accIds]);
                    
                    for (CareObservation rec : toSend) {
                        Account acc = accMap.get(rec.ObservedSubjectId);
                        if (acc == null || acc.PersonContactId == null) continue;
                        
                        String vitalType = VITAL_NAME_MAP.get(rec.Name.toLowerCase());
                        
                        Map<String, Object> payload = new Map<String, Object>{
                            'id'         => rec.Id,
                             'user_id'    => acc.PersonContactId,
                             'vitals'     => new List<Map<String, String>>{
                                    new Map<String, String>{
                                        'vital_type' => vitalType,
                                            'value'      => String.valueOf(rec.Value_Quantity__c)
                                            }
                                },
                                    'created_at' => rec.CreatedDate
                                    };
                                        sendRequest(cs.Vitals_API__c, payload);
                    }
                }
    
    private static void sendRequest(String endpoint, Map<String, Object> payload) {
        try {
            String requestBody = JSON.serialize(payload);
            System.debug(LoggingLevel.DEBUG, 'Vitals API Payload: ' + requestBody);
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(requestBody);
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                System.debug(LoggingLevel.DEBUG, 'Vitals API Success: ' + res.getBody());
            } else {
                System.debug(LoggingLevel.ERROR, 'Vitals API Failed. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Vitals API Exception: ' + e.getMessage());
        }
    }
}