@RestResource(urlMapping='/publicfields/*')
global without sharing class PublicFieldListApi {

    @HttpGet
    global static void getFields() {
        RestRequest req = RestContext.request;
        String responsebody = req.requestBody.toString();
        system.debug('responsebody>>>'+responsebody);

        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        res.addHeader('Access-Control-Allow-Origin', '*');
        res.addHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        res.addHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
        res.addHeader('Content-Type', 'application/json');

        String objectName = req.params.get('sobject');
        if (String.isBlank(objectName)) {
            objectName = req.params.get('object');
        }

        if (String.isBlank(objectName)) {
            writeError(400, 'Pass ?sobject=Lead or ?object=Account');
            return;
        }

        Map<String, Schema.SObjectType> allObjects = Schema.getGlobalDescribe();
        Schema.SObjectType targetType;
        String resolvedObjectName;

        for (String apiName : allObjects.keySet()) {
            if (apiName != null && apiName.toLowerCase() == objectName.toLowerCase()) {
                targetType = allObjects.get(apiName);
                resolvedObjectName = apiName;
                break;
            }
        }

        if (targetType == null) {
            writeError(404, 'Invalid object name: ' + objectName);
            return;
        }

        Schema.DescribeSObjectResult objectDescribe = targetType.getDescribe();

        // Object-level read check
        if (!objectDescribe.isAccessible()) {
            writeError(403, 'No access to object: ' + resolvedObjectName);
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        List<String> fieldNames = new List<String>();

        for (String fieldApiName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();

            // Field-level read check
            if (fieldDescribe.isAccessible()) {
                fieldNames.add(fieldApiName);
            }
        }

        fieldNames.sort();

        // Exact response format: ["LastName","Status__c","Website"]
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(fieldNames));
    }

    private static void writeError(Integer statusCode, String message) {
        RestResponse res = RestContext.response;

        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        res.addHeader('Content-Type', 'application/json');
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(message)));
    }

    global class ErrorResponse {
        global Boolean success = false;
        global String message;

        global ErrorResponse(String message) {
            this.message = message;
        }
    }
}