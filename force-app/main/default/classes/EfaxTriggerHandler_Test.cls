@isTest
public class EfaxTriggerHandler_Test {
    
    @isTest(SeeAllData=true)
    static void setupData() {
        
        Id paRtId = ContactMedicalDataAPI.getPersonAccountRecordTypeId();
        Account pa = new Account(
            RecordTypeId = paRtId,
            FirstName = 'Test',
            LastName = 'Patient',
            Suffix = 'Jr',
            status__c = 'Active',
            PersonEmail = 'patient@test.com',
            PersonMobilePhone = '9999999999'
        );
        insert pa;
        
        
        Id outboundRecordTypeId;
        for (RecordType rt : [SELECT Id, Name, SObjectType FROM RecordType WHERE SObjectType = 'smsefax_guru__eFAX__c']) {
            if (rt.Name == 'OutBound eFAX') {
                outboundRecordTypeId = rt.Id;
                break;
            }
        }
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test',
            PathOnClient = 'test.pdf',
            VersionData = Blob.valueOf('test'),
            Source__c = 'Metriport'
        );
        insert cv;
        
        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
        
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = pa.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        
        smsefax_guru__eFAX__c faxValid = new smsefax_guru__eFAX__c();
        faxValid.smsefax_guru__User_s_E_Fax_Number__c = '+11234567890';
        faxValid.smsefax_guru__Customer_s_eFAX_Number__c = '+11234567890';
        faxValid.smsefax_guru__ContentVersionId__c = cv.Id;
        faxValid.RecordTypeId = outboundRecordTypeId;
        faxValid.smsefax_guru__Parent_Record_Id__c = pa.Id;
        faxValid.smsefax_guru__Send_Cover_Letter__c = true;
        
        Test.startTest();
        insert faxValid;
        Test.stopTest();
        
    }
}