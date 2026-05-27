public class HealthConditionSorter implements Comparator<HealthCondition> {
    public Integer compare(HealthCondition a, HealthCondition b) {

        // ✅ Active first
        if (a.ConditionStatus == 'Active' && b.ConditionStatus != 'Active') return -1;
        if (a.ConditionStatus != 'Active' && b.ConditionStatus == 'Active') return 1;

        // ✅ Then latest first
        if (a.CreatedDate > b.CreatedDate) return -1;
        if (a.CreatedDate < b.CreatedDate) return 1;

        return 0;
    }
}