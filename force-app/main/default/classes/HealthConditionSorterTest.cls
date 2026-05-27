@isTest(seeAllData=true)
private class HealthConditionSorterTest {

    @isTest
    static void testSortingLogic() {

        // ✅ Fetch Person Account (Patient)
        List<Account> paList = [
            SELECT Id 
            FROM Account 
            WHERE IsPersonAccount = true 
            LIMIT 1
        ];
        System.assert(!paList.isEmpty(), 'No Person Account found in org');
        Account patient = paList[0];

        // ✅ Create HealthCondition records
        HealthCondition c1 = new HealthCondition(
            ConditionStatus = 'Active',
            PatientId = patient.Id
        );

        HealthCondition c2 = new HealthCondition(
            ConditionStatus = 'Inactive',
            PatientId = patient.Id
        );

        HealthCondition c3 = new HealthCondition(
            ConditionStatus = 'Active',
            PatientId = patient.Id
        );

        insert new List<HealthCondition>{ c1, c2, c3 };

        // Re-query to get CreatedDate
        List<HealthCondition> conditions = [
            SELECT Id, ConditionStatus, CreatedDate
            FROM HealthCondition
            WHERE Id IN :new List<Id>{c1.Id, c2.Id, c3.Id}
        ];

        // Shuffle list (important)
        conditions = new List<HealthCondition>{
            conditions[1], conditions[2], conditions[0]
        };

        // Sort
        conditions.sort(new HealthConditionSorter());

        // ✅ Assertions

        // Active first
        System.assertEquals('Active', conditions[0].ConditionStatus);
        System.assertEquals('Active', conditions[1].ConditionStatus);
        System.assertNotEquals('Active', conditions[2].ConditionStatus);

        // Latest first within Active
        System.assert(
            conditions[0].CreatedDate >= conditions[1].CreatedDate,
            'Active conditions should be sorted by latest CreatedDate'
        );
    }
}