public without sharing class CaseMetriportController {
    
    @AuraEnabled
    public static String sendCaseFiles(Id caseId) {
        
        // 1️⃣ Get Case + Patient Info
        Case c = [
            SELECT Id, Subject, Account.Name, Account.Metriport_Patient_Id__c, CreatedDate
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        
        if (c.Account == null || String.isBlank(c.Account.Metriport_Patient_Id__c)) {
            throw new AuraHandledException('Metriport Patient ID not found on account.');
        }
        
        // 2️⃣ Get files linked to Case
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :caseId
        ];
        
        if (links.isEmpty()) {
            throw new AuraHandledException('No files found on this Case.');
        }
        
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) {
            docIds.add(l.ContentDocumentId);
        }
        
        // 🔥 IMPORTANT: Added FileExtension
        List<ContentVersion> versions = [
            SELECT Id, Title, VersionData, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            AND IsLatest = true
        ];
        
        for (ContentVersion cv : versions) {
            
            String documentTypeText = cv.Title;
            String loincCode = '34133-9';
            String loincDisplay = c.Subject;
            String facilityType = 'Medical Summary';
            String startDate = c.CreatedDate.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            
            // ✅ Proper file name (no double extension issue)
            String fileName = cv.Title.contains('.') 
                ? cv.Title 
                : cv.Title + '.' + cv.FileExtension;
            
            System.enqueueJob(
                new MetriportUploadQueueable(
                    c.Account.Metriport_Patient_Id__c,
                    c.Account.Name,
                    cv.VersionData,     // ✅ DIRECT BLOB (NO BASE64)
                    fileName,
                    cv.FileExtension,
                    documentTypeText,
                    loincCode,
                    loincDisplay,
                    facilityType,
                    startDate,
                    c.Id
                )
            );
        }
        
        return 'Files sent successfully to Metriport';
    }
}