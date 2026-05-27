public class MedicationSorter implements Comparator<MedicationStatement> {
    public Integer compare(MedicationStatement a, MedicationStatement b) {

        // ✅ Active should come first
        if (a.Status == 'Active' && b.Status != 'Active') return -1;
        if (a.Status != 'Active' && b.Status == 'Active') return 1;

        // ✅ Then sort by latest CreatedDate
        if (a.CreatedDate > b.CreatedDate) return -1;
        if (a.CreatedDate < b.CreatedDate) return 1;

        return 0;
    }
}