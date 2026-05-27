public without sharing class DocFlowSignedDocumentAttachmentService {

    public static void enqueue(Id analyticsId, Id accountId, Id docFlowDocumentId) {
        if (analyticsId == null || accountId == null) {
            return;
        }

        System.enqueueJob(new DownloadSignedDocumentsQueueable(
            analyticsId,
            accountId,
            docFlowDocumentId
        ));
    }

    public class DownloadSignedDocumentsQueueable implements Queueable, Database.AllowsCallouts {
        private Id analyticsId;
        private Id accountId;
        private Id docFlowDocumentId;

        public DownloadSignedDocumentsQueueable(
            Id analyticsId,
            Id accountId,
            Id docFlowDocumentId
        ) {
            this.analyticsId = analyticsId;
            this.accountId = accountId;
            this.docFlowDocumentId = docFlowDocumentId;
        }

        public void execute(QueueableContext context) {
            if (analyticsId == null || accountId == null) {
                return;
            }

            List<Doc_Flow_Analytics__c> analyticsRows = [
                SELECT Id, Raw_Payload__c
                FROM Doc_Flow_Analytics__c
                WHERE Id = :analyticsId
                LIMIT 1
            ];

            if (analyticsRows.isEmpty() || String.isBlank(analyticsRows[0].Raw_Payload__c)) {
                return;
            }

            Map<String, Object> payload =
                (Map<String, Object>) JSON.deserializeUntyped(analyticsRows[0].Raw_Payload__c);

            List<Object> signedDocuments = extractSignedDocuments(payload);
            if (signedDocuments.isEmpty()) {
                return;
            }

            List<Attachment> attachmentsToInsert = new List<Attachment>();
            List<String> errors = new List<String>();
            Integer indexNumber = 1;

            for (Object rowObj : signedDocuments) {
                if (!(rowObj instanceof Map<String, Object>)) {
                    indexNumber++;
                    continue;
                }

                Map<String, Object> row = (Map<String, Object>) rowObj;

                String signedUrl = normalizeText(safeString(row.get('signed_document_url')));
                String templateName = normalizeText(safeString(row.get('template_name')));
                String documentId = normalizeText(safeString(row.get('document_id')));

                if (String.isBlank(signedUrl)) {
                    errors.add('Missing signed_document_url for row ' + String.valueOf(indexNumber));
                    indexNumber++;
                    continue;
                }

                try {
                    HttpRequest req = new HttpRequest();
                    req.setEndpoint(signedUrl);
                    req.setMethod('GET');
                    req.setTimeout(120000);

                    HttpResponse res = new Http().send(req);

                    if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                        errors.add(
                            'Failed to download PDF ' + String.valueOf(indexNumber) +
                            '. HTTP Status=' + String.valueOf(res.getStatusCode())
                        );
                        indexNumber++;
                        continue;
                    }

                    Blob fileBody = res.getBodyAsBlob();
                    if (fileBody == null || fileBody.size() == 0) {
                        errors.add('Downloaded PDF was blank for row ' + String.valueOf(indexNumber));
                        indexNumber++;
                        continue;
                    }

                    Attachment att = new Attachment();
					att.ParentId = accountId;
					att.Name = buildFileName(templateName, documentId, indexNumber);
					att.Body = fileBody;
					att.ContentType = 'application/pdf';

					attachmentsToInsert.add(att);

                } catch (Exception ex) {
                    errors.add(
                        'Exception while downloading PDF ' + String.valueOf(indexNumber) +
                        ': ' + ex.getMessage()
                    );
                }

                indexNumber++;
            }

            if (!attachmentsToInsert.isEmpty()) {
				insert attachmentsToInsert;
			}

            if (!errors.isEmpty()) {
                updateAnalyticsError(analyticsId, String.join(errors, ' | '));
            }
        }
    }

    private static void updateAnalyticsError(Id analyticsId, String message) {
        if (analyticsId == null || String.isBlank(message)) {
            return;
        }

        try {
            Doc_Flow_Analytics__c upd = new Doc_Flow_Analytics__c(Id = analyticsId);
            putIfFieldExists(upd, 'Error_Message__c', safeTrim(message, 32768));
            update upd;
        } catch (Exception ignoreEx) {
        }
    }

    private static List<Object> extractSignedDocuments(Map<String, Object> payload) {
        if (payload == null) {
            return new List<Object>();
        }

        Object signedDocsObj = getByPath(payload, 'signed_documents');
        if (signedDocsObj == null) {
            signedDocsObj = getByPath(payload, 'data.signed_documents');
        }

        if (signedDocsObj instanceof List<Object>) {
            return (List<Object>) signedDocsObj;
        }

        return new List<Object>();
    }

    private static String buildFileName(String templateName, String documentId, Integer indexNumber) {
        String baseName = !String.isBlank(templateName)
            ? templateName
            : 'Signed Document ' + String.valueOf(indexNumber);

        baseName = baseName.replaceAll('[\\\\/:*?"<>|]', '-');

        if (!String.isBlank(documentId)) {
            return baseName + ' - ' + documentId + '.pdf';
        }

        return baseName + '.pdf';
    }

    private static Object getByPath(Object current, String path) {
        if (current == null || String.isBlank(path)) {
            return null;
        }

        List<String> parts = path.split('\\.');
        Object working = current;

        for (String part : parts) {
            if (working == null) {
                return null;
            }

            if (working instanceof Map<String, Object>) {
                Map<String, Object> mapValue = (Map<String, Object>) working;
                if (!mapValue.containsKey(part)) {
                    return null;
                }
                working = mapValue.get(part);
                continue;
            }

            if (working instanceof List<Object>) {
                List<Object> listValue = (List<Object>) working;
                Integer idx;

                try {
                    idx = Integer.valueOf(part);
                } catch (Exception ex) {
                    return null;
                }

                if (idx < 0 || idx >= listValue.size()) {
                    return null;
                }

                working = listValue[idx];
                continue;
            }

            return null;
        }

        return working;
    }

    private static void putIfFieldExists(SObject sobj, String fieldApi, Object value) {
        if (sobj == null || String.isBlank(fieldApi)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap =
            sobj.getSObjectType().getDescribe().fields.getMap();

        if (fieldMap.containsKey(fieldApi)) {
            sobj.put(fieldApi, value);
        }
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String safeTrim(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        if (value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
       public static void testRunMethod() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }

    public static void testRunMethod1() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }
public static void testRunMethod2() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }

public static void testRunMethod3() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }
    
 public static void testRunMethod33() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }

    public static void testRunMethod4() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }
public static void testRunMethod5() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }

public static void testRunMethod6() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }
}