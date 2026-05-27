@isTest(SeeAllData=true)
public class AiGeneratedSummaryTitleFixBatchTest {
    
    @isTest
    static void testBatchSetFalse() {
        
        Account acc = [SELECT Id FROM Account WHERE Metriport_Patient_Id__c  = 'patient-123' LIMIT 1];
        
        ContentVersion sourceCV = new ContentVersion(
            Title = 'Test Metriport File',
            PathOnClient = 'TestMetriportFile.pdf',
            VersionData = Blob.valueOf('Test Content'),
            Source__c = 'metriport',
            Send_File_to_Portal__c = true,
            FirstPublishLocationId = acc.Id
        );
        insert sourceCV;
        
        ContentVersion aiCV = new ContentVersion(
            Title = 'Test AI Summary File',
            PathOnClient = 'TestAISummaryFile.pdf',
            VersionData = Blob.valueOf('AI Summary Content'),
            Related_File__c = sourceCV.Id,
            Send_File_to_Portal__c = true
        );
        insert aiCV;
        
        Test.startTest();
        Database.executeBatch(new AiGeneratedSummaryTitleFixBatch(false), 1);
        Test.stopTest();
        
        ContentVersion updatedAiCV = [
            SELECT Id, Send_File_to_Portal__c
            FROM ContentVersion
            WHERE Id = :aiCV.Id
        ];
        
        System.assertEquals(false, updatedAiCV.Send_File_to_Portal__c, 
            'Send_File_to_Portal__c should be false');
    }
    
    @isTest
    static void testBatchSetTrue() {
        
        Account acc = [SELECT Id FROM Account WHERE Metriport_Patient_Id__c  = 'patient-123' LIMIT 1];
        
        ContentVersion sourceCV = new ContentVersion(
            Title = 'Test Metriport File',
            PathOnClient = 'TestMetriportFile.pdf',
            VersionData = Blob.valueOf('Test Content'),
            Source__c = 'metriport',
            Send_File_to_Portal__c = true,
            FirstPublishLocationId = acc.Id
        );
        insert sourceCV;
        
        ContentVersion aiCV = new ContentVersion(
            Title = 'Test AI Summary File',
            PathOnClient = 'TestAISummaryFile.pdf',
            VersionData = Blob.valueOf('AI Summary Content'),
            Related_File__c = sourceCV.Id,
            Send_File_to_Portal__c = false
        );
        insert aiCV;
        
        Test.startTest();
        Database.executeBatch(new AiGeneratedSummaryTitleFixBatch(true), 1);
        Test.stopTest();
        
        ContentVersion updatedAiCV = [
            SELECT Id, Send_File_to_Portal__c
            FROM ContentVersion
            WHERE Id = :aiCV.Id
        ];
        
        System.assertEquals(true, updatedAiCV.Send_File_to_Portal__c, 
            'Send_File_to_Portal__c should be true');
    }
}