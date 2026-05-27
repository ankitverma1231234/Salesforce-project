@isTest(seeAllData=true)
private class MedicationSorterTest {

    @isTest
    static void testSortingLogic() {

        // ✅ Fetch existing Medication
        List<Medication> medList = [
            SELECT Id 
            FROM Medication 
            LIMIT 1
        ];
        System.assert(!medList.isEmpty(), 'No Medication found in org');
        Medication med = medList[0];

        // ✅ Fetch Person Account (Patient)
        List<Account> paList = [
            SELECT Id 
            FROM Account 
            WHERE IsPersonAccount = true 
            LIMIT 1
        ];
        System.assert(!paList.isEmpty(), 'No Person Account found in org');
        Account patient = paList[0];

        // ✅ Create MedicationStatement records
        MedicationStatement m1 = new MedicationStatement(
            Status = 'Active',
            MedicationId = med.Id,
            PatientId = patient.Id
        );

        MedicationStatement m2 = new MedicationStatement(
            Status = 'Completed',
            MedicationId = med.Id,
            PatientId = patient.Id
        );

        MedicationStatement m3 = new MedicationStatement(
            Status = 'Active',
            MedicationId = med.Id,
            PatientId = patient.Id
        );

        insert new List<MedicationStatement>{ m1, m2, m3 };

        // Re-query for CreatedDate
        List<MedicationStatement> meds = [
            SELECT Id, Status, CreatedDate
            FROM MedicationStatement
            WHERE Id IN :new List<Id>{m1.Id, m2.Id, m3.Id}
        ];

        // Shuffle list (important)
        meds = new List<MedicationStatement>{ meds[1], meds[2], meds[0] };

        // Sort
        meds.sort(new MedicationSorter());

        // ✅ Assertions
        System.assertEquals('Active', meds[0].Status);
        System.assertEquals('Active', meds[1].Status);
        System.assertNotEquals('Active', meds[2].Status);

        System.assert(
            meds[0].CreatedDate >= meds[1].CreatedDate,
            'Active should be latest first'
        );
    }
}