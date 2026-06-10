@IsTest(SeeAllData=true)
private class AttachmentServiceTest {
    @IsTest
    static void createAttachmentCreatesLogAndJsonPayload() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Clinical Summary',
            'ClinicalSummary.pdf',
            'test content'
        );
        String jsonData = JSON.serialize(new Map<String, Object>{
            'contentVersionId' => version.Id,
                'title' => version.Title
                });
        
        AttachmentService.createAttachment(jsonData, version.Id);
        
        Document_Processing_Log__c logRecord = [
            SELECT Id, Attachment_Id__c, Attachment_Created_On__c,
            Ready_for_Ai_Naming__c, Current_Status__c,
            Error_Message__c, Is_Active__c
            FROM Document_Processing_Log__c
            WHERE Content_Version_Id__c = :version.Id
            LIMIT 1
        ];
        System.assertEquals('Attachment Created', logRecord.Current_Status__c);
        System.assertEquals(null, logRecord.Error_Message__c);
        System.assertEquals(true, logRecord.Is_Active__c);
        System.assertEquals(true, logRecord.Ready_for_Ai_Naming__c);
        System.assertNotEquals(null, logRecord.Attachment_Id__c);
        System.assertNotEquals(null, logRecord.Attachment_Created_On__c);
        
        Attachment createdAttachment = [
            SELECT Name, Body, ParentId, ContentType, Description
            FROM Attachment
            WHERE Id = :logRecord.Attachment_Id__c
        ];
        System.assertEquals('Clinical Summary.json', createdAttachment.Name);
        System.assertEquals(logRecord.Id, createdAttachment.ParentId);
        System.assertEquals('application/json', createdAttachment.ContentType);
        System.assertEquals(
            'Internal document-processing payload. Do not sync to Google Drive.',
            createdAttachment.Description
        );
        System.assertEquals(jsonData, createdAttachment.Body.toString());
    }
    
    @IsTest
    static void createAttachmentReplacesExistingAttachment() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Replacement Source',
            'ReplacementSource.pdf',
            'test content'
        );
        
        AttachmentService.createAttachment('{"revision":1}', version.Id);
        Document_Processing_Log__c firstLog = [
            SELECT Id, Attachment_Id__c
            FROM Document_Processing_Log__c
            WHERE Content_Version_Id__c = :version.Id
            LIMIT 1
        ];
        Id firstAttachmentId = firstLog.Attachment_Id__c;
        
        AttachmentService.createAttachment('{"revision":2}', version.Id);
        
        Document_Processing_Log__c updatedLog = [
            SELECT Id, Attachment_Id__c, Current_Status__c,
            Ready_for_Ai_Naming__c
            FROM Document_Processing_Log__c
            WHERE Content_Version_Id__c = :version.Id
            LIMIT 1
        ];
        System.assertEquals(firstLog.Id, updatedLog.Id);
        System.assertNotEquals(firstAttachmentId, updatedLog.Attachment_Id__c);
        System.assertEquals('Attachment Created', updatedLog.Current_Status__c);
        System.assertEquals(true, updatedLog.Ready_for_Ai_Naming__c);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Attachment WHERE Id = :firstAttachmentId]
        );
        
        Attachment replacement = [
            SELECT Body
            FROM Attachment
            WHERE Id = :updatedLog.Attachment_Id__c
        ];

    }

    private static Account getExistingAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
    }
}