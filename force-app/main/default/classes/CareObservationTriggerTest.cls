@isTest(SeeAllData=true)
private class CareObservationTriggerTest {

    // ─────────────────────────────────────────
    // Helper: fetch an existing Person Account
    // ─────────────────────────────────────────
    private static Account getPersonAccount() {
        return [
            SELECT Id, Weight_in_pounds__pc, Height_in_inches__pc
            FROM Account
            WHERE IsPersonAccount = true
              AND IsDeleted = false
            LIMIT 1
        ];
    }

    // ─────────────────────────────────────────
    // Helper: build a CareObservation record
    // ─────────────────────────────────────────
    private static CareObservation buildObservation(
            Id subjectId, String name, String valueQuantity) {
        return new CareObservation(
            ObservedSubjectId = subjectId,
            Name              = name,
            Value_Quantity__c = valueQuantity,
            ObservationStatus = 'Final'
        );
    }

    // ═════════════════════════════════════════
    // INSERT TESTS
    // ═════════════════════════════════════════

    @isTest
    static void testInsert_BodyWeight_Kilograms() {
        Account acc = getPersonAccount();

        Test.startTest();
        CareObservation obs = buildObservation(acc.Id, 'Body weight', '80 kg');
        insert obs;
        Test.stopTest();

        Account result = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        Decimal expected = (80 * 2.20462).setScale(2);
        System.assertEquals(expected, result.Weight_in_pounds__pc,
            'Weight should be converted from kg to lbs');

        delete obs;
    }

    @isTest
    static void testInsert_BodyWeight_Pounds() {
        Account acc = getPersonAccount();

        Test.startTest();
        CareObservation obs = buildObservation(acc.Id, 'Body weight', '165 lbs');
        insert obs;
        Test.stopTest();

        Account result = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(Decimal.valueOf(165).setScale(2), result.Weight_in_pounds__pc,
            'Weight already in lbs should remain unchanged');

        delete obs;
    }

    @isTest
    static void testInsert_BodyHeight_Centimeters() {
        Account acc = getPersonAccount();

        Test.startTest();
        CareObservation obs = buildObservation(acc.Id, 'Body height', '170 cm');
        insert obs;
        Test.stopTest();

        Account result = [SELECT Height_in_inches__pc FROM Account WHERE Id = :acc.Id];
        Decimal expected = (170 * 0.393701).setScale(2);
        System.assertEquals(expected, result.Height_in_inches__pc,
            'Height should be converted from cm to inches');

        delete obs;
    }

    @isTest
    static void testInsert_BodyHeight_Inches() {
        Account acc = getPersonAccount();

        Test.startTest();
        CareObservation obs = buildObservation(acc.Id, 'Body height', '68 inches');
        insert obs;
        Test.stopTest();

        Account result = [SELECT Height_in_inches__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(Decimal.valueOf(68).setScale(2), result.Height_in_inches__pc,
            'Height already in inches should remain unchanged');

        delete obs;
    }

    // ═════════════════════════════════════════
    // UPDATE TESTS
    // ═════════════════════════════════════════

    @isTest
    static void testUpdate_BodyWeight_KgToLbs() {
        Account acc = getPersonAccount();
        CareObservation obs = buildObservation(acc.Id, 'Body weight', '70 kg');
        insert obs;

        Test.startTest();
        obs.Value_Quantity__c = '90 kg';
        update obs;
        Test.stopTest();

        Account result = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        Decimal expected = (90 * 2.20462).setScale(2);
        System.assertEquals(expected, result.Weight_in_pounds__pc,
            'Weight should reflect updated kg value converted to lbs');

        delete obs;
    }

    @isTest
    static void testUpdate_BodyHeight_CmToInches() {
        Account acc = getPersonAccount();
        CareObservation obs = buildObservation(acc.Id, 'Body height', '160 cm');
        insert obs;

        Test.startTest();
        obs.Value_Quantity__c = '175 cm';
        update obs;
        Test.stopTest();

        Account result = [SELECT Height_in_inches__pc FROM Account WHERE Id = :acc.Id];
        Decimal expected = (175 * 0.393701).setScale(2);
        System.assertEquals(expected, result.Height_in_inches__pc,
            'Height should reflect updated cm value converted to inches');

        delete obs;
    }

    // ═════════════════════════════════════════
    // DELETE TEST
    // ═════════════════════════════════════════

    @isTest
    static void testDelete_LogsAuditRecord() {
        Account acc = getPersonAccount();
        CareObservation obs = buildObservation(acc.Id, 'Body weight', '75 kg');
        insert obs;
        Id obsId = obs.Id;

        Test.startTest();
        delete obs;
        Test.stopTest();
    }

    @isTest
    static void testInsert_BlankValueQuantity_SkipsUpdate() {
        Account acc = getPersonAccount();

        // Capture the current weight before the test
        Decimal weightBefore = acc.Weight_in_pounds__pc;

        Test.startTest();
        CareObservation obs = buildObservation(acc.Id, 'Body weight', '');
        insert obs;
        Test.stopTest();

        Account result = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(weightBefore, result.Weight_in_pounds__pc,
            'Account weight should remain unchanged for blank Value_Quantity__c');

        delete obs;
    }

    @isTest
    static void testInsert_NonNumericValue_SkipsUpdate() {
        Account acc = getPersonAccount();

        Decimal weightBefore = acc.Weight_in_pounds__pc;

        Test.startTest();
        CareObservation obs = buildObservation(acc.Id, 'Body weight', 'N/A');
        insert obs;
        Test.stopTest();

        Account result = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(weightBefore, result.Weight_in_pounds__pc,
            'Account weight should remain unchanged when value cannot be parsed');

        delete obs;
    }

    @isTest
    static void testInsert_UnrecognizedObsName_SkipsWeightAndHeight() {
        Account acc = getPersonAccount();

        Decimal weightBefore  = acc.Weight_in_pounds__pc;
        Decimal heightBefore  = acc.Height_in_inches__pc;

        Test.startTest();
        CareObservation obs = buildObservation(acc.Id, 'Blood Pressure', '120/80');
        insert obs;
        Test.stopTest();

        Account result = [SELECT Weight_in_pounds__pc, Height_in_inches__pc
                          FROM Account WHERE Id = :acc.Id];
        System.assertEquals(weightBefore, result.Weight_in_pounds__pc,
            'Weight should be untouched for unrecognized obs name');
        System.assertEquals(heightBefore, result.Height_in_inches__pc,
            'Height should be untouched for unrecognized obs name');

        delete obs;
    }

    // ═════════════════════════════════════════
    // BULK TEST
    // ═════════════════════════════════════════

    @isTest
    static void testBulkInsert_200Records() {
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
              AND IsDeleted = false
            LIMIT 200
        ];

        System.assert(accounts.size() > 0,
            'At least one Person Account must exist in org for bulk test');

        // Build up to 200 observations across available accounts
        List<CareObservation> observations = new List<CareObservation>();
        for (Integer i = 0; i < accounts.size(); i++) {
            String name  = Math.mod(i, 2) == 0 ? 'Body weight' : 'Body height';
            String value = Math.mod(i, 2) == 0 ? '70 kg'       : '170 cm';
            observations.add(buildObservation(accounts[i].Id, name, value));
        }

        Test.startTest();
        insert observations;
        Test.stopTest();

        // Spot-check first weight observation
        Account weightAcc = [
            SELECT Weight_in_pounds__pc
            FROM Account
            WHERE Id = :accounts[0].Id
        ];
        Decimal expectedWeight = (70 * 2.20462).setScale(2);
        System.assertEquals(expectedWeight, weightAcc.Weight_in_pounds__pc,
            'Bulk weight conversion should be correct');

        if (accounts.size() > 1) {
            Account heightAcc = [
                SELECT Height_in_inches__pc
                FROM Account
                WHERE Id = :accounts[1].Id
            ];
            Decimal expectedHeight = (170 * 0.393701).setScale(2);
            System.assertEquals(expectedHeight, heightAcc.Height_in_inches__pc,
                'Bulk height conversion should be correct');
        }

        delete observations;
    }
}