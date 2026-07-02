public class MetriportFetchPatientSummary {
    @future(callout=true)
    public static void fetchPatientSummary(String patientId) {
        if (String.isBlank(patientId)) return;
        Metriport_Config__mdt meta;
        try {
            meta = [
                SELECT API_Key__c, Base_URL__c
                FROM Metriport_Config__mdt
                WHERE Active__c = true
                LIMIT 1
            ];
        } catch (Exception e) {
            return;
        }
        if (meta == null ||
            String.isBlank(meta.API_Key__c) ||
            String.isBlank(meta.Base_URL__c)) {
            return;
        }
        Id patientSfId;
        try {
            patientSfId = [
                SELECT Id
                FROM Account
                WHERE Metriport_Patient_Id__c = :patientId
                LIMIT 1
            ].Id;
        } catch (Exception e) {
            return;
        }
        // 1️⃣ Get the document download URL
        String urlEndpoint =
            meta.Base_URL__c +
            '/medical/v1/patient/' +
            EncodingUtil.urlEncode(patientId, 'UTF-8') +
            '/medical-record?conversionType=pdf';
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(urlEndpoint);
        req.setMethod('GET');
        req.setHeader('x-api-key', meta.API_Key__c);
        req.setTimeout(120000);
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            return;
        }
        if (res == null || res.getStatusCode() != 200) return;
        Map<String, Object> respMap;
        try {
            respMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            return;
        }
        if (respMap == null || !respMap.containsKey('url')) return;
        String downloadUrl = (String) respMap.get('url');
        if (String.isBlank(downloadUrl)) return;
        // 2️⃣ Download the PDF from the URL
        HttpRequest downloadReq = new HttpRequest();
        downloadReq.setEndpoint(downloadUrl);
        downloadReq.setMethod('GET');
        downloadReq.setTimeout(120000);
        HttpResponse downloadRes;
        try {
            downloadRes = http.send(downloadReq);
        } catch (Exception e) {
            return;
        }
        if (downloadRes == null || downloadRes.getStatusCode() != 200) return;
        Blob pdfBlob = downloadRes.getBodyAsBlob();
        if (pdfBlob == null) return;
        // 🔎 Check if "Medical Summary" file already exists for this patient
        List<ContentDocumentLink> existingFiles = [
            SELECT ContentDocumentId,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :patientSfId
            AND ContentDocument.Title = 'Medical Summary'
            LIMIT 1
        ];
        if (!existingFiles.isEmpty()) {
            // File already exists → do not insert again
            return;
        }
        // 🔎 Check if a Deleted_Record_Audit__c exists for this patient's Medical Summary
        List<Deleted_Record_Audit__c> deletedAudit = [
            SELECT Id
            FROM Deleted_Record_Audit__c
            WHERE Object_API_Name__c = 'ContentVersion'
            AND External_Id_Metriport__c = 'Medical Summary'
            AND Parent_Record_Id__c = :patientSfId
            LIMIT 1
        ];
        if (!deletedAudit.isEmpty()) {
            // Medical Summary was previously deleted for this patient → do not re-insert
            return;
        }
        // 3️⃣ Insert Document_Reference__c
       /* Document_Reference__c docRef = new Document_Reference__c();
        docRef.Patient__c = patientSfId;
        docRef.Name__c = 'Medical Summary';
        docRef.Status__c = 'current';
        docRef.File_Name__c = 'Medical_Summary_' + patientId + '.pdf';
        insert docRef; */
        // 4️⃣ Attach the PDF as ContentVersion
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Medical Summary';
        cv.PathOnClient = 'Medical_Summary_' + patientId + '.pdf';
        cv.VersionData = pdfBlob;
        cv.FirstPublishLocationId = patientSfId;
        cv.Source_Type__c = 'Metriport';
        cv.Send_File_to_Portal__c = true;
        insert cv;
    }
}