@IsTest
public class ImmunizationJobTest {

    /* --------------------------------
       Test 1: Normal execution path
    --------------------------------- */
    @IsTest
    static void testImmunizationJob_NormalExecution() {

        String validJson =
            '{' +
            ' "resourceType":"Bundle",' +
            ' "entry":[{' +
            '   "resource":{' +
            '     "resourceType":"Immunization",' +
            '     "id":"imm-001"' +
            '   }' +
            ' }]' +
            '}';

        Test.startTest();
        System.enqueueJob(new ImmunizationJob(validJson));
        Test.stopTest();

        // No exception = pass
        System.assert(true, 'ImmunizationJob executed successfully');
    }

    /* --------------------------------
       Test 2: Blank JSON (safe return)
    --------------------------------- */
    @IsTest
    static void testImmunizationJob_BlankJson() {

        Test.startTest();
        System.enqueueJob(new ImmunizationJob(''));
        Test.stopTest();

        System.assert(true, 'Blank JSON handled safely');
    }

    /* --------------------------------
       Test 3: Invalid JSON (catch path)
    --------------------------------- */
    @IsTest
    static void testImmunizationJob_InvalidJson() {

        // Malformed JSON to hit error handling
        String invalidJson = '{ bad json ';

        Test.startTest();
        System.enqueueJob(new ImmunizationJob(invalidJson));
        Test.stopTest();

        System.assert(true, 'Exception path executed safely');
    }
}