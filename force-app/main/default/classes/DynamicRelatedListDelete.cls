public with sharing class DynamicRelatedListDelete {

    public String  toastType    { get; private set; }
    public String  toastMessage { get; private set; }
    public String  accountId    { get; private set; }

    private final ApexPages.StandardSetController setCon;

    // ─── Constructor ──────────────────────────────────────────────────────────
    public DynamicRelatedListDelete(ApexPages.StandardSetController controller) {
        this.setCon    = controller;
        this.accountId = resolveAccountId();
    }

    // ─── Resolve Account Id ───────────────────────────────────────────────────
    private String resolveAccountId() {

        // 1️⃣ Parse retURL — handles /lightning/r/Account/<id>/view
        String retUrl = ApexPages.currentPage().getParameters().get('retURL');
        if (String.isNotBlank(retUrl)) {
            List<String> parts = retUrl.split('/');
            for (Integer i = 0; i < parts.size(); i++) {
                if (parts[i] == 'Account' && i + 1 < parts.size()) {
                    String candidate = parts[i + 1];
                    if (candidate.length() == 15 || candidate.length() == 18) {
                        return candidate;
                    }
                }
            }
        }

        // 2️⃣ Direct accountId query parameter
        String paramId = ApexPages.currentPage().getParameters().get('accountId');
        if (String.isNotBlank(paramId)) return paramId;

        // 3️⃣ Dynamically find Account lookup on whatever object is in the list
        try {
            List<SObject> selected = setCon.getSelected();
            if (selected == null || selected.isEmpty()) return null;

            String objectName       = selected[0].getSObjectType().getDescribe().getName();
            String accountFieldName = findAccountLookupField(objectName);
            if (String.isBlank(accountFieldName)) return null;

            Set<Id> ids   = new Map<Id, SObject>(selected).keySet();
            String  query = 'SELECT ' + accountFieldName
                          + ' FROM '  + objectName
                          + ' WHERE Id IN :ids LIMIT 1';

            List<SObject> results = Database.query(query);
            if (!results.isEmpty()) {
                Id acctId = (Id) results[0].get(accountFieldName);
                if (acctId != null) return acctId;
            }
        } catch (Exception ex) { /* skip silently */ }

        return null;
    }

    // ─── Find Account Lookup Field ────────────────────────────────────────────
    private String findAccountLookupField(String objApiName) {
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objApiName);
        if (objType == null) return null;

        Map<String, Schema.SObjectField> fields = objType.getDescribe().fields.getMap();
        for (String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult fd = fields.get(fieldName).getDescribe();
            if (fd.getType() != Schema.DisplayType.REFERENCE) continue;
            for (Schema.SObjectType ref : fd.getReferenceTo()) {
                if (ref.getDescribe().getName() == 'Account') return fd.getName();
            }
        }
        return null;
    }

    // ─── VF Action ────────────────────────────────────────────────────────────
    public PageReference autoDelete() {
        List<SObject> selectedRecords = setCon.getSelected();

        if (selectedRecords == null || selectedRecords.isEmpty()) {
            toastType    = 'warning';
            toastMessage = 'No records were selected for deletion.';
            return null;
        }

        // Collect Ids and object type
        String   objectApiName = selectedRecords[0].getSObjectType().getDescribe().getName();
        List<Id> recordIds     = new List<Id>();
        for (SObject rec : selectedRecords) {
            recordIds.add(rec.Id);
        }

        try {
            // Hand off to the batch — controller holds NO batch state
            Database.executeBatch(
                new DynamicRelatedListDeleteController(recordIds, objectApiName),
                200
            );
            toastType    = 'success';
            toastMessage = selectedRecords.size() + ' record(s) queued for deletion.';
        } catch (Exception e) {
            toastType    = 'error';
            toastMessage = 'Failed to queue deletion: ' + e.getMessage();
        }

        return null;
    }
}