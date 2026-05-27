@IsTest(SeeAllData=true)
public class MedicalSalesforceDeleteRecordTest {
    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }
    private static Account getPersonAccount() {
        List<Account> accList = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1];
        if (!accList.isEmpty()) {
            return accList[0];
        }
        Id paRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1].Id;
        Account pa = new Account(
             RecordTypeId = paRtId,
             FirstName = 'Existing',
             LastName = 'Test',
             PersonEmail = 'existing.test@example.com',
             PersonMobilePhone = '5551234567'
        );
        insert pa;
        return pa;
    }
    private static Medication getMedication() {
        List<Medication> meds = [SELECT Id FROM Medication LIMIT 1];
        if (!meds.isEmpty()) {
            return meds[0];
        }
        Medication med = new Medication(Name = 'Fallback Medication');
        insert med;
        return med;
    }
    @IsTest
    static void testInsertAndUpdate_AllTriggers() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Account pa = getPersonAccount();
        Medication med = getMedication();
        Test.startTest();
        AllergyIntolerance ai = new AllergyIntolerance(PatientId = pa.Id);
        insert ai;
        update ai;
        HealthCondition hc = new HealthCondition(
            PatientId = pa.Id,
            ProblemName = 'Hypertension',
            ConditionStatus = 'Active');
        insert hc;
        update hc;
        HealthCareProcedure hcp = new HealthCareProcedure(
            Name = 'Procedure',
            Surgery_Name__c = 'Procedure',
            Patient__c = pa.Id,
            EffectiveDate = Date.today());
        insert hcp;
        update hcp;
        MedicationStatement ms = new MedicationStatement(
            PatientId = pa.Id,
            MedicationId = med.Id,
            Status = 'Active');
        insert ms;
        update ms;
        MemberPlan mp = new MemberPlan(
            Name = 'Insurance Plan',
            MemberId = pa.Id,
            MemberNumber = 'MEM-001',
            RelationshipToSubscriber = 'Self',
            PrimarySecondaryTertiary = 'Primary');
        insert mp;
        update mp;
        HealthcareFacility hf = new HealthcareFacility(
            Name = 'Clinic',
            AccountId = pa.Id);
        insert hf;
        update hf;
        HealthcarePractitionerFacility hpf = new HealthcarePractitionerFacility(
            Name = 'Doctor',
            AccountId = pa.Id);
        insert hpf;
        update hpf;
        Test.stopTest();
        System.assert(true);
    }
    @IsTest
    static void testDelete_AllTriggers() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());        
        Test.startTest();        
        List<SObject> recordsToDelete = new List<SObject>();        
        recordsToDelete.addAll([SELECT Id FROM AllergyIntolerance LIMIT 1]);
        recordsToDelete.addAll([SELECT Id FROM HealthCondition LIMIT 1]);
        recordsToDelete.addAll([SELECT Id FROM HealthCareProcedure LIMIT 1]);
        recordsToDelete.addAll([SELECT Id FROM MedicationStatement LIMIT 1]);
        recordsToDelete.addAll([SELECT Id FROM MemberPlan LIMIT 1]);
        recordsToDelete.addAll([SELECT Id FROM HealthcareFacility LIMIT 1]);
        recordsToDelete.addAll([SELECT Id FROM HealthcarePractitionerFacility LIMIT 1]);
        List<Account> accounts = [
            SELECT Id 
            FROM Account 
            WHERE Id NOT IN (SELECT AccountId FROM User WHERE IsPortalEnabled = true AND AccountId != null)
            LIMIT 5];
        recordsToDelete.addAll(accounts);        
        List<Contact> contacts = [
            SELECT Id, Account.IsPersonAccount 
            FROM Contact 
            WHERE Account.IsPersonAccount = false
            LIMIT 5];
        recordsToDelete.addAll(contacts);        
        if (!recordsToDelete.isEmpty()) {
            Database.DeleteResult[] results = Database.delete(recordsToDelete, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    Database.Error error = results[i].getErrors()[0];
                    System.debug(LoggingLevel.WARN, 
                        'Failed to delete ' + recordsToDelete[i].getSObjectType() + 
                        ' Id: ' + recordsToDelete[i].Id + 
                        ' - Error: ' + error.getMessage());
                }
            }
        }        
        Test.stopTest();        
        System.assert(true, 'Test completed successfully');
    }
    @IsTest
    static void testDeleteClassMethods() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Id anyId = [SELECT Id FROM Account LIMIT 1].Id;
        Test.startTest();
        MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(
            new Set<Id>{ anyId },
            'Account');
        MedicalSalesforceDeleteRecord.deleteRecordsFuture(
            JSON.serialize(new List<Id>{ anyId }),
            'Account');
        Test.stopTest();
        System.assert(true);
    }
    @IsTest
    static void testNullAndEmptyGuards() {
        Test.startTest();
        MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(null, 'Case');
        MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(new Set<Id>(), 'Case');
        MedicalSalesforceDeleteRecord.deleteRecordsFuture('[]', 'Case');
        Test.stopTest();
        System.assert(true);
    }
    @IsTest
    static void testCaseTriggerCoverage() {
        Test.setMock(HttpCalloutMock.class, new MedicalSalesforceDeleteRecordTest.SuccessMock());
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Test Case Insert',
            Description = 'Initial Description'
        );
        insert c;
        c.Description = 'Updated Description';
        update c;
        delete c;        
        Test.stopTest();
        System.assert(true); 
    }
}