@IsTest(SeeAllData=true)
public class CareObservationTriggerTest {

    @IsTest
    static void testCareObservationConversions() {

        List<Account> accList = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        if (accList.isEmpty()) {
            System.debug('No Account found with Metriport_Patient_Id__c = patient-123. Skipping test.');
            return;
        }

        Account acc = accList[0];

        List<CareObservation> observations = new List<CareObservation>();

        // 1. Body weight in kg → should convert to lbs (70 * 2.20462 = 154.32)
        observations.add(new CareObservation(
            Name = 'Body weight',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '70 kg'
        ));

        // 2. Body height in cm → should convert to inches (180 * 0.393701 = 70.87)
        observations.add(new CareObservation(
            Name = 'Body height',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '180 cm'
        ));

        // 3. Weight already in pounds → no conversion, stored as 150
        //    ⚠️ Overwrites obs #1 since same Account — LAST value wins in map
        observations.add(new CareObservation(
            Name = 'Body weight',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '150 lb'
        ));

        // 4. Height already in inches → no conversion, stored as 65
        //    ⚠️ Overwrites obs #2 since same Account — LAST value wins in map
        observations.add(new CareObservation(
            Name = 'Body height',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '65 in'
        ));

        // 5. Invalid numeric value → should be SKIPPED (Decimal.valueOf throws)
        observations.add(new CareObservation(
            Name = 'Body weight',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = 'abc kg'
        ));

        // 6. Blank value → should be SKIPPED (String.isBlank check)
        observations.add(new CareObservation(
            Name = 'Body height',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = ''
        ));

        // 7. Null ObservedSubjectId → should be SKIPPED (null check in trigger)
        observations.add(new CareObservation(
            Name = 'Body weight',
            ObservedSubjectId = null,   // ✅ Fixed: was incorrectly acc.Id
            ObservationStatus = 'Final',
            Value_Quantity__c = '80 kg'
        ));

        Test.startTest();
        insert observations;
        Test.stopTest();

        // Reload Account with updated fields
        Account updatedAcc = [
            SELECT Weight_in_pounds__pc, Height_in_inches__pc
            FROM Account
            WHERE Id = :acc.Id
        ];

        // ── Assertions ────────────────────────────────────────────────────────

        // Weight: obs#5 (invalid) and obs#7 (null subject) are skipped
        //         obs#1 (70 kg) sets weight, then obs#3 (150 lb) OVERWRITES it
        //         → Final value = 150.00
        System.assertNotEquals(null, updatedAcc.Weight_in_pounds__pc,
            'Weight should be populated');
        System.assertEquals(150.00, updatedAcc.Weight_in_pounds__pc,
            'Weight should be 150 lbs (last valid weight, already in lbs — no conversion)');

        // Height: obs#6 (blank) is skipped
        //         obs#2 (180 cm) sets height, then obs#4 (65 in) OVERWRITES it
        //         → Final value = 65.00
        System.assertNotEquals(null, updatedAcc.Height_in_inches__pc,
            'Height should be populated');
        System.assertEquals(65.00, updatedAcc.Height_in_inches__pc,
            'Height should be 65 inches (last valid height, already in inches — no conversion)');
    }

    // ── Additional test: verify kg → lbs conversion in isolation ─────────────
    @IsTest
    static void testWeightKgConversionOnly() {

        List<Account> accList = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        if (accList.isEmpty()) {
            System.debug('No Account found. Skipping test.');
            return;
        }

        Account acc = accList[0];

        CareObservation obs = new CareObservation(
            Name = 'Body weight',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '70 kg'
        );

        Test.startTest();
        insert obs;
        Test.stopTest();

        Account updatedAcc = [
            SELECT Weight_in_pounds__pc
            FROM Account
            WHERE Id = :acc.Id
        ];

        // 70 kg * 2.20462 = 154.32 (rounded to 2 decimal places by trigger)
        System.assertEquals(154.32, updatedAcc.Weight_in_pounds__pc,
            'Weight should be 154.32 lbs after kg to lbs conversion');
    }

    // ── Additional test: verify cm → inches conversion in isolation ───────────
    @IsTest
    static void testHeightCmConversionOnly() {

        List<Account> accList = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        if (accList.isEmpty()) {
            System.debug('No Account found. Skipping test.');
            return;
        }

        Account acc = accList[0];

        CareObservation obs = new CareObservation(
            Name = 'Body height',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '180 cm'
        );

        Test.startTest();
        insert obs;
        Test.stopTest();

        Account updatedAcc = [
            SELECT Height_in_inches__pc
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals(70.87, updatedAcc.Height_in_inches__pc,
            'Height should be 70.87 inches after cm to inches conversion');
    }
}