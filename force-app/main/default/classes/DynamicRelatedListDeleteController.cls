public with sharing class DynamicRelatedListDeleteController {
    
    private ApexPages.StandardSetController setCon;
    public String toastType    { get; private set; }
    public String toastMessage { get; private set; }
    public String accountId    { get; private set; }
    
    public DynamicRelatedListDeleteController(ApexPages.StandardSetController controller) {
        this.setCon = controller;
        this.accountId = resolveAccountId();
    }    
    private String resolveAccountId() {        
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
        String paramId = ApexPages.currentPage().getParameters().get('accountId');
        if (String.isNotBlank(paramId)) {
            return paramId;
        }        
        try {
            List<SObject> selected = setCon.getSelected();
            if (selected == null || selected.isEmpty()) return null;            
            String objectApiName = selected[0].getSObjectType().getDescribe().getName();            
            String accountFieldName = findAccountLookupField(objectApiName);
            if (String.isBlank(accountFieldName)) return null;            
            Set<Id> ids = new Map<Id, SObject>(selected).keySet();
            String query = 'SELECT ' + accountFieldName +
                ' FROM ' + objectApiName +
                ' WHERE Id IN :ids LIMIT 1';            
            List<SObject> results = Database.query(query);
            if (!results.isEmpty()) {
                Id acctId = (Id) results[0].get(accountFieldName);
                if (acctId != null) return acctId;
            }            
        } catch (Exception ex) {
        }
        
        return null;
    }
    private String findAccountLookupField(String objectApiName) {
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return null;        
        Map<String, Schema.SObjectField> fields = objType.getDescribe().fields.getMap();        
        for (String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult fieldDesc = fields.get(fieldName).getDescribe();
            Schema.DisplayType fieldType = fieldDesc.getType();           
            if (fieldType != Schema.DisplayType.REFERENCE) continue;            
            for (Schema.SObjectType ref : fieldDesc.getReferenceTo()) {
                if (ref.getDescribe().getName() == 'Account') {
                    return fieldDesc.getName(); // return the API field name
                }
            }
        }        
        return null; // no Account lookup found
    }
    
    public PageReference autoDelete() {
        List<SObject> selectedRecords = setCon.getSelected();        
        if (selectedRecords == null || selectedRecords.isEmpty()) {
            toastType    = 'warning';
            toastMessage = 'No records were selected for deletion.';
            return null;
        }        
        Database.DeleteResult[] results = Database.delete(selectedRecords, false);
        Integer successCount = 0;
        List<String> errorMessages = new List<String>();        
        for (Database.DeleteResult res : results) {
            if (res.isSuccess()) {
                successCount++;
            } else {
                for (Database.Error err : res.getErrors()) {
                    errorMessages.add(err.getMessage());
                }
            }
        }        
        if (successCount > 0) {
            toastType    = 'success';
            toastMessage = successCount + ' record(s) deleted successfully.';
        }        
        if (!errorMessages.isEmpty()) {
            toastType    = 'error';
            toastMessage = 'Failed to delete ' + (results.size() - successCount) + ' record(s): ' 
                + String.join(errorMessages, '; ');
        }        
        return null;
    }
}