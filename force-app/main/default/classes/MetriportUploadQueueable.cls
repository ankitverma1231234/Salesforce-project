public class MetriportUploadQueueable implements Queueable, Database.AllowsCallouts {
    
    
private String metriportPatientId;
    private String patientName;
    private Blob fileBlob;           // ✅ FIXED
    private String fileName;
    private String fileExtension;
    
    private String documentTypeText;
    private String loincCode;
    private String loincDisplay;
    private String facilityType;
    private String startDate;
    private Id caseId;
    
    private static Metriport_Config__mdt cachedConfig;
    
    public MetriportUploadQueueable(
        String metriportPatientId,
        String patientName,
        Blob fileBlob,               // ✅ FIXED
        String fileName,
        String fileExtension,
        String documentTypeText,
        String loincCode,
        String loincDisplay,
        String facilityType,
        String startDate,
        Id caseId
    ) {
        this.metriportPatientId = metriportPatientId;
        this.patientName        = patientName;
        this.fileBlob           = fileBlob;
        this.fileName           = fileName;
        this.fileExtension      = fileExtension;
        this.documentTypeText   = documentTypeText;
        this.loincCode          = loincCode;
        this.loincDisplay       = loincDisplay;
        this.facilityType       = facilityType;
        this.startDate          = startDate;
        this.caseId             = caseId;
    }
    
    private static Metriport_Config__mdt getActiveConfig() {
        if (cachedConfig != null) return cachedConfig;
        
        cachedConfig = [
            SELECT API_Key__c, Base_URL__c
            FROM Metriport_Config__mdt
            WHERE Active__c = true
            LIMIT 1
        ];
        
        return cachedConfig;
    }
    
    public void execute(QueueableContext context) {
    try {

        System.debug('=== Metriport Upload Started ===');
        System.debug('Case Id: ' + caseId);
        System.debug('Patient Id: ' + metriportPatientId);
        System.debug('File Name: ' + fileName);

        Http http = new Http();
        Metriport_Config__mdt config = getActiveConfig();

        System.debug('Base URL: ' + config.Base_URL__c);

        // STEP 1: Create Document Reference
        String docRefBody = JSON.serialize(new Map<String, Object>{
            'type' => new Map<String, Object>{
                'text' => documentTypeText,
                'coding' => new List<Object>{
                    new Map<String, Object>{
                        'system'  => 'http://loinc.org',
                        'code'    => loincCode,
                        'display' => loincDisplay
                    }
                }
            },
            'description' => fileName,
            'content' => new List<Object>{
                new Map<String, Object>{
                    'attachment' => new Map<String, Object>{
                        'title' => fileName,
                        'contentType' => getMimeType(fileExtension)
                    }
                }
            },
            'context' => new List<Object>{
                new Map<String, Object>{
                    'period' => new Map<String, Object>{
                        'start' => startDate
                    },
                    'facilityType' => new Map<String, Object>{
                        'text' => facilityType
                    }
                }
            }
        });

        System.debug('Document Reference Request Body: ' + docRefBody);

        HttpRequest docRefReq = new HttpRequest();
        docRefReq.setEndpoint(config.Base_URL__c +
            '/medical/v1/document/upload?patientId=' +
            metriportPatientId);

        docRefReq.setMethod('POST');
        docRefReq.setHeader('Content-Type', 'application/json');
        docRefReq.setHeader('x-api-key', config.API_Key__c);
        docRefReq.setBody(docRefBody);

        System.debug('Sending Document Reference Request...');

        HttpResponse docRefRes = http.send(docRefReq);

        System.debug('Document Reference Status Code: ' +
            docRefRes.getStatusCode());

        System.debug('Document Reference Response: ' +
            docRefRes.getBody());

        if (docRefRes.getStatusCode() != 200 &&
            docRefRes.getStatusCode() != 201) {

            throw new CalloutException(
                'Document Reference Creation Failed: ' +
                docRefRes.getBody()
            );
        }

        Map<String, Object> response =
            (Map<String, Object>)JSON.deserializeUntyped(
                docRefRes.getBody()
            );

        String uploadUrl = (String)response.get('uploadUrl');

        System.debug('Upload URL Received: ' + uploadUrl);

        // STEP 2: Upload File
        HttpRequest uploadReq = new HttpRequest();
        uploadReq.setEndpoint(uploadUrl);
        uploadReq.setMethod('PUT');
        uploadReq.setHeader(
            'Content-Type',
            getMimeType(fileExtension)
        );
        uploadReq.setBodyAsBlob(fileBlob);

        System.debug('Uploading file to Metriport...');
        System.debug('File Size (Bytes): ' + fileBlob.size());

        HttpResponse uploadRes = http.send(uploadReq);

        System.debug('Upload Status Code: ' +
            uploadRes.getStatusCode());

        System.debug('Upload Response Body: ' +
            uploadRes.getBody());

        if (uploadRes.getStatusCode() != 200 &&
            uploadRes.getStatusCode() != 204) {

            throw new CalloutException(
                'File Upload Failed: ' +
                uploadRes.getBody()
            );
        }

        System.debug('File uploaded successfully.');

        // Update Case
        Case c = new Case(
            Id = caseId,
            Send_File_To_Metriport__c = true,
            Status = 'Closed'
        );

        update c;

        System.debug('Case Updated Successfully');
        System.debug('Case Status Changed To Closed');
        System.debug('=== Metriport Upload Completed ===');

    } catch (Exception e) {

        System.debug('=== ERROR OCCURRED ===');
        System.debug('Error Message: ' + e.getMessage());
        System.debug('Stack Trace: ' + e.getStackTraceString());

        throw e;
    }
}
    
    // 🔥 Helper for correct MIME type
    private static String getMimeType(String ext) {
        ext = ext != null ? ext.toLowerCase() : '';
        
        if (ext == 'pdf') return 'application/pdf';
        if (ext == 'png') return 'image/png';
        if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
        if (ext == 'docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        
        return 'application/octet-stream';
    }
}