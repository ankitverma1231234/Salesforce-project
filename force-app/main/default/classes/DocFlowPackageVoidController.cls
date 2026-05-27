public with sharing class DocFlowPackageVoidController {

    private static final String BASE_URL = 'https://api.cluvik.com';
    private static final String API_KEY = 'dfk_AeSCS10hxyricKBkgudeuCyW5y09MRN8gaNcpCGzIOI';

    public class InitResponse {
        @AuraEnabled public Id docFlowDocumentId { get; set; }
        @AuraEnabled public String docFlowDocumentName { get; set; }
        @AuraEnabled public String documentRuntimeId { get; set; }
        @AuraEnabled public String packageRuntimeId { get; set; }
        @AuraEnabled public String packageBlueprintId { get; set; }
        @AuraEnabled public String packageName { get; set; }
        @AuraEnabled public String documentStatus { get; set; }
        @AuraEnabled public String primaryAccessLink { get; set; }
        @AuraEnabled public String sourceRecordId { get; set; }
        @AuraEnabled public Boolean alreadyVoided { get; set; }
    }

    public class VoidActionResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Boolean alreadyVoided { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String documentId { get; set; }
        @AuraEnabled public String voidedAt { get; set; }
        @AuraEnabled public String voidReason { get; set; }
    }

    @AuraEnabled
    public static InitResponse getVoidInitData(Id docFlowDocumentId) {
        if (docFlowDocumentId == null) {
            throw new AuraHandledException('Doc Flow Document Id is required.');
        }

        Doc_Flow_Document__c doc = [
            SELECT Id,
                   Name,
                   Status__c,
                   Template_Id__c,
                   Document_Id__c,
                   Document_Name__c,
                   Primary_Access_Link__c,
                   Source_Record_Id__c,
                   Response_Json__c,
                   Package_Metadata_Json__c,
                   Template_Metadata_Json__c,
                   DocFlow_Source_Type__c
            FROM Doc_Flow_Document__c
            WHERE Id = :docFlowDocumentId
            LIMIT 1
        ];

        Map<String, Object> responseJson = parseJsonMap(doc.Response_Json__c);
        Map<String, Object> packageMetaJson = parseJsonMap(doc.Package_Metadata_Json__c);
        Map<String, Object> templateMetaJson = parseJsonMap(doc.Template_Metadata_Json__c);
		String sourceType = blankToEmpty(safeString(doc.get('DocFlow_Source_Type__c'))).toLowerCase();

        String resolvedDocumentId = firstNonBlank(
            doc.Document_Id__c,
            extractFirstDocumentId(responseJson)
        );

        InitResponse response = new InitResponse();
        response.docFlowDocumentId = doc.Id;
        response.docFlowDocumentName = firstNonBlank(
            doc.Document_Name__c,
            doc.Name
        );
        response.documentRuntimeId = resolvedDocumentId;
        response.packageRuntimeId = firstNonBlank(
            safeString(responseJson.get('run_id')),
            safeString(responseJson.get('package_id'))
        );
        response.packageBlueprintId = doc.Template_Id__c;
        String resolvedSourceName;

if (sourceType == 'template') {
    String templateMetaName = firstNonBlank(
        safeString(templateMetaJson.get('templateName')),
        safeString(templateMetaJson.get('template_name'))
    );

    resolvedSourceName = firstNonBlank(
        templateMetaName,
        firstNonBlank(
            safeString(responseJson.get('template_name')),
            firstNonBlank(doc.Document_Name__c, doc.Name)
        )
    );
} else {
    resolvedSourceName = firstNonBlank(
        safeString(packageMetaJson.get('packageName')),
        firstNonBlank(
            safeString(responseJson.get('package_name')),
            firstNonBlank(doc.Document_Name__c, doc.Name)
        )
    );
}

response.packageName = resolvedSourceName;
        response.documentStatus = doc.Status__c;
        response.primaryAccessLink = doc.Primary_Access_Link__c;
        response.sourceRecordId = doc.Source_Record_Id__c;
        response.alreadyVoided = 'voided' == blankToEmpty(doc.Status__c).toLowerCase();

        return response;
    }

    @AuraEnabled
    public static VoidActionResponse voidPackage(Id docFlowDocumentId, String reason) {
        if (docFlowDocumentId == null) {
            throw new AuraHandledException('Doc Flow Document Id is required.');
        }

        Doc_Flow_Document__c doc = [
            SELECT Id,
                   Name,
                   Status__c,
                   Template_Id__c,
                   Document_Id__c,
                   Document_Name__c,
                   Response_Json__c,
                   Error_Message__c
            FROM Doc_Flow_Document__c
            WHERE Id = :docFlowDocumentId
            LIMIT 1
        ];

        if ('voided' == blankToEmpty(doc.Status__c).toLowerCase()) {
            VoidActionResponse already = new VoidActionResponse();
            already.success = true;
            already.alreadyVoided = true;
            already.documentId = doc.Document_Id__c;
            already.message = 'Document is already voided.';
            return already;
        }

        Map<String, Object> responseJson = parseJsonMap(doc.Response_Json__c);

        String documentRuntimeId = firstNonBlank(
            doc.Document_Id__c,
            extractFirstDocumentId(responseJson)
        );

        if (String.isBlank(documentRuntimeId)) {
            throw new AuraHandledException(
                'Document id was not found. Please confirm the Doc Flow Document record has Document_Id__c populated or a valid Response_Json__c.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            BASE_URL +
            '/api/docflow/public/documents/' +
            EncodingUtil.urlEncode(documentRuntimeId, 'UTF-8') +
            '/void'
        );
        req.setMethod('POST');
        req.setHeader('X-API-Key', API_KEY);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);

        Map<String, Object> body = new Map<String, Object>();
        if (!String.isBlank(reason)) {
            body.put('reason', reason.trim());
        }
        req.setBody(JSON.serialize(body));

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception ex) {
            throw new AuraHandledException('Document void callout failed: ' + ex.getMessage());
        }

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            String msg = 'Document void API failed. HTTP ' + res.getStatusCode() + ' - ' + res.getStatus();
            if (!String.isBlank(res.getBody())) {
                msg += ' | Response=' + res.getBody();
            }
            throw new AuraHandledException(msg);
        }

        Map<String, Object> resBody = parseJsonMap(res.getBody());

        Doc_Flow_Document__c upd = new Doc_Flow_Document__c(Id = doc.Id);
        putIfFieldExists(upd, 'Status__c', 'voided');
        putIfFieldExists(upd, 'Error_Message__c', null);
        putIfFieldExists(upd, 'Void_Reason__c', String.isBlank(reason) ? null : reason.trim());
        update upd;

        VoidActionResponse response = new VoidActionResponse();
        response.success = normalizeBoolean(resBody.get('success')) || !normalizeBoolean(resBody.get('already_voided'));
        response.alreadyVoided = normalizeBoolean(resBody.get('already_voided'));
        response.documentId = firstNonBlank(
            safeString(resBody.get('document_id')),
            documentRuntimeId
        );
        response.voidedAt = safeString(resBody.get('voided_at'));
        response.voidReason = firstNonBlank(
            safeString(resBody.get('void_reason')),
            reason
        );
        response.message = response.alreadyVoided
            ? 'Document was already voided.'
            : 'Document voided successfully.';

        return response;
    }

    private static String extractFirstDocumentId(Map<String, Object> responseJson) {
        if (responseJson == null || !responseJson.containsKey('documents')) {
            return null;
        }

        List<Object> docs = (List<Object>) responseJson.get('documents');
        if (docs == null || docs.isEmpty()) {
            return null;
        }

        Object firstObj = docs[0];
        if (!(firstObj instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> firstDoc = (Map<String, Object>) firstObj;
        return safeString(firstDoc.get('document_id'));
    }

    private static Map<String, Object> parseJsonMap(String rawJson) {
        if (String.isBlank(rawJson)) {
            return new Map<String, Object>();
        }

        try {
            Object parsed = JSON.deserializeUntyped(rawJson);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
        } catch (Exception ex) {
        }

        return new Map<String, Object>();
    }

    private static String firstNonBlank(String value1, String value2) {
        return !String.isBlank(value1) ? value1 : value2;
    }

    private static String firstNonBlank(String value1, String value2, String value3) {
        if (!String.isBlank(value1)) return value1;
        if (!String.isBlank(value2)) return value2;
        return value3;
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    private static Boolean normalizeBoolean(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean) value;
        return 'true' == String.valueOf(value).toLowerCase();
    }

    private static void putIfFieldExists(SObject sobj, String fieldApi, Object value) {
        if (sobj == null || String.isBlank(fieldApi)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = sobj.getSObjectType().getDescribe().fields.getMap();
        if (fieldMap.containsKey(fieldApi)) {
            sobj.put(fieldApi, value);
        }
    }
}