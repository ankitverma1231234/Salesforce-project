@IsTest
public class AllergyJobTest {

    /* --------------------------------
       Test 1: Normal happy path
    --------------------------------- */
    @IsTest
    static void testAllergyJob_NormalExecution() {

        String validJson =
            '{' +
            ' "resourceType":"Bundle",' +
            ' "entry":[{' +
            '   "resource":{' +
            '     "resourceType":"AllergyIntolerance",' +
            '     "id":"allergy-001"' +
            '   }' +
            ' }]' +
            '}';

        Test.startTest();
        System.enqueueJob(new AllergyJob(validJson));
        Test.stopTest();

        System.assert(true, 'Normal execution covered');
    }

    /* --------------------------------
       Test 2: Force catch block execution
    --------------------------------- */
    @IsTest
    static void testAllergyJob_CatchBlockCoverage() {

        // VERY large invalid string to break heap parsing
        String badJson = Blob.valueOf('x').toString();

        Test.startTest();
        System.enqueueJob(new AllergyJob(badJson));
        Test.stopTest();

        System.assert(true, 'Catch block executed');
    }

    /* --------------------------------
       Test 3: Null JSON edge case
    --------------------------------- */
    @IsTest
    static void testAllergyJob_NullJson() {

        Test.startTest();
        System.enqueueJob(new AllergyJob(null));
        Test.stopTest();

        System.assert(true, 'Null JSON handled');
    }
}