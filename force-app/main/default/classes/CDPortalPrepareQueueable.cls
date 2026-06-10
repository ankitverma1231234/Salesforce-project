public class CDPortalPrepareQueueable implements Queueable {
    private List<Id> fileStorageIds;
    public CDPortalPrepareQueueable(List<Id> fileStorageIds) {
        this.fileStorageIds = fileStorageIds;
    }
    
    public void execute(QueueableContext qc){
        BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
        if (apiConfig == null || String.isBlank(apiConfig.Api_Key__c)) return;
        
        Map<Id,fra__File_Storage__c> fileStorageMap = new Map<Id,fra__File_Storage__c>();
        for(fra__File_Storage__c fs: [
            SELECT Id,
            fra__File_Id__c,
            Fra_AI_Source_File_Id__c,
            Name,
            Send_to_Portal__c,
            fra__File_Public_Url__c,
            fra__File_Size__c,
            fra__File_Type__c,
            Source_Type__c,
            Date_of_Service_Display__c,
            Document_Type__c,
            Category__c,
            fra__Internal_File_Id__c,
            fra__Entity_Storage__c,
            Related_Summary_File__c
            FROM fra__File_Storage__c
            WHERE Id IN :fileStorageIds
            AND   Send_to_Portal__c = true
        ]){
            fileStorageMap.put(fs.Id, fs);
        }
        if (fileStorageMap.isEmpty()) return;
        
        Set<Id> entityStorageIds = new Set<Id>();
        for (fra__File_Storage__c fs : fileStorageMap.values()) {
            if (fs.fra__Entity_Storage__c != null) {
                entityStorageIds.add(fs.fra__Entity_Storage__c);
            }
        }
        if(entityStorageIds.isEmpty()) return;
        
        List<fra__Entity_Storage__c> entityStorageList = [
            SELECT Id, fra__File_Store_Record_Id__c
            FROM fra__Entity_Storage__c
            WHERE Id IN :entityStorageIds
        ];
        if (entityStorageList.isEmpty()) return;
        
         Map<Id, Id> entityToAccountMap = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>();
        for (fra__Entity_Storage__c es : entityStorageList) {
            if (String.isNotBlank(es.fra__File_Store_Record_Id__c)) {
                Id accountId = (Id) es.fra__File_Store_Record_Id__c;
                entityToAccountMap.put(es.Id, accountId);
                accountIds.add(accountId);
            }
        }
        if(accountIds.isEmpty()) return;
        
        Map<Id, Id> accountToContactMap = new Map<Id, Id>();
        for (Contact c : [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId IN :accountIds
        ]) {
            if (!accountToContactMap.containsKey(c.AccountId)) {
                accountToContactMap.put(c.AccountId, c.Id);
            }
        }
        
        Map<Id, List<Map<String, Object>>> accountDocumentsMap = new Map<Id, List<Map<String, Object>>>();
        for (fra__File_Storage__c fs : fileStorageMap.values()){
            Id entityStorageId = fs.fra__Entity_Storage__c;
            Id accountId       = entityToAccountMap.get(entityStorageId);
            if (accountId == null) continue;
            
            Map<String, Object> doc = new Map<String, Object>();
            doc.put('Id',            fs.fra__Internal_File_Id__c              != null ? fs.fra__Internal_File_Id__c                        : '');
            doc.put('recordId',      String.valueOf(fs.Id));
            doc.put('Title',         fs.Name                         != null ? fs.Name                                   : '');
            doc.put('PublicUrl',     fs.fra__File_Public_Url__c      != null ? fs.fra__File_Public_Url__c                : '');
            doc.put('ContentSize',   fs.fra__File_Size__c            != null ? String.valueOf(fs.fra__File_Size__c)      : '');
            doc.put('FileType',      fs.fra__File_Type__c            != null ? fs.fra__File_Type__c                      : '');
            doc.put('source_type',   fs.Source_Type__c               != null ? fs.Source_Type__c                         : '');
            doc.put('CreatedDate',   fs.Date_of_Service_Display__c   != null ? String.valueOf(fs.Date_of_Service_Display__c) : '');
            doc.put('document_type', fs.Document_Type__c             != null ? fs.Document_Type__c                       : '');
            doc.put('category',      fs.Category__c                  != null ? fs.Category__c                            : '');
            doc.put('accountId',     String.valueOf(accountId));
            doc.put('relatedFile',   fs.Fra_AI_Source_File_Id__c     != null ? fs.Fra_AI_Source_File_Id__c               : '');
            
            if (!accountDocumentsMap.containsKey(accountId)) {
                accountDocumentsMap.put(accountId, new List<Map<String, Object>>());
            }
            accountDocumentsMap.get(accountId).add(doc);
        }
        
        List<String> payloads = new List<String>();
        
        for(Id accountId : accountDocumentsMap.keySet()){
            Map<String, Object> payload = new Map<String, Object>();
            if (accountToContactMap.containsKey(accountId)) {
                payload.put('contactId', accountToContactMap.get(accountId));
            }
            payload.put('documents', accountDocumentsMap.get(accountId));
            payloads.add(JSON.serialize(payload));
            System.debug('payload >> ' + JSON.serializePretty(payload));
            
        }
        
        if (!Test.isRunningTest() && !payloads.isEmpty()) {
            System.enqueueJob(
                new ContentDocumentQueueable(payloads)
            );
        }
    }
}