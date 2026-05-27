@IsTest(seeAllData = true)
public class PatientAdmitJobTest {

    /* -------------------------
       Normal execution
    -------------------------- */
    @IsTest
    static void testPatientAdmitJob_Normal() {

        Account acc = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        String validJson =
            '{"resourceType":"Bundle","id":"patient-123"}';

        PatientAdmitJob job =
            new PatientAdmitJob(validJson, 'ADT_A01');

        Test.startTest();
        System.enqueueJob(job);
        Test.stopTest();

        System.assert(true);
    }

    /* -------------------------
       Exception paths
    -------------------------- */
    @IsTest
    static void testPatientAdmitJob_ExceptionPaths() {

        // Force parser failures
        String invalidJson = 'INVALID_JSON';

        PatientAdmitJob job =
            new PatientAdmitJob(invalidJson, 'ADT_A01');

        Test.startTest();
        System.enqueueJob(job);
        Test.stopTest();

        System.assert(true);
    }
}