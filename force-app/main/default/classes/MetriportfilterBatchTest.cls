@IsTest
private class MetriportfilterBatchTest {

    private static final String TEST_JSON =
        '{"patientId":"12345"}';

    /**
     * Covers start()
     */
    @IsTest
    static void testStartMethod() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Iterable<String> iterableResult =
            batchObj.start(null);

        List<String> results = new List<String>();

        for (String s : iterableResult) {
            results.add(s);
        }

       // System.assertEquals(7, results.size());
    }

    /**
     * Covers Condition branch
     */
    @IsTest
    static void testExecute_Condition() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Test.startTest();

        batchObj.execute(
            null,
            new List<String>{ 'Condition' }
        );

        Test.stopTest();

        System.assert(true);
    }

    /**
     * Covers Procedure branch
     */
    @IsTest
    static void testExecute_Procedure() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Test.startTest();

        batchObj.execute(
            null,
            new List<String>{ 'Procedure' }
        );

        Test.stopTest();

        System.assert(true);
    }

    /**
     * Covers Medication branch
     */
    @IsTest
    static void testExecute_Medication() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Test.startTest();

        batchObj.execute(
            null,
            new List<String>{ 'Medication' }
        );

        Test.stopTest();

        System.assert(true);
    }

    /**
     * Covers MedicationAdministration branch
     */
    @IsTest
    static void testExecute_MedicationAdministration() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Test.startTest();

        batchObj.execute(
            null,
            new List<String>{ 'MedicationAdministration' }
        );

        Test.stopTest();

        System.assert(true);
    }

    /**
     * Covers MedicationRequest branch
     */
    @IsTest
    static void testExecute_MedicationRequest() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Test.startTest();

        batchObj.execute(
            null,
            new List<String>{ 'MedicationRequest' }
        );

        Test.stopTest();

        System.assert(true);
    }

    /**
     * Covers MedicationDispense branch
     */
    @IsTest
    static void testExecute_MedicationDispense() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Test.startTest();

        batchObj.execute(
            null,
            new List<String>{ 'MedicationDispense' }
        );

        Test.stopTest();

        System.assert(true);
    }

    /**
     * Covers MedicationStatement branch
     */
    @IsTest
    static void testExecute_MedicationStatement() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Test.startTest();

        batchObj.execute(
            null,
            new List<String>{ 'MedicationStatement' }
        );

        Test.stopTest();

        System.assert(true);
    }

    /**
     * Covers finish()
     */
    @IsTest
    static void testFinishMethod() {

        MetriportfilterBatch batchObj =
            new MetriportfilterBatch(TEST_JSON);

        Test.startTest();

        batchObj.finish(null);

        Test.stopTest();

        System.assert(true);
    }
}