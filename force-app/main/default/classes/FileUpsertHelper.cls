public Without Sharing class FileUpsertHelper {

    public static List<Map<String, Object>> processFiles(List<Map<String, Object>> records) {

        List<Map<String, Object>> resultData = new List<Map<String, Object>>();

        if(records == null || records.isEmpty()){
            return resultData;
        }

        List<ContentVersion> toInsert = new List<ContentVersion>();
        List<ContentVersion> toUpdate = new List<ContentVersion>();
        List<String>         fileRangerCVIds = new List<String>();

        Map<Integer, Map<String, Object>> insertIndexMap = new Map<Integer, Map<String, Object>>();

        for(Map<String, Object> recData : records){

            if(recData == null) continue;

            String id = (String)recData.get('id');
            String recordId = (String)recData.get('recordid');
            Object deleteFlag = recData.get('is_deleted');
            
            Boolean isDelete = false;
            
            if(deleteFlag != null){
                isDelete = (deleteFlag instanceof Boolean)
                    ? (Boolean) deleteFlag
                    : String.valueOf(deleteFlag).toLowerCase() == 'true';
            }
            
            if(!String.isBlank(recordId) && isDelete){
                fileRangerCVIds.add(recordId);
                recData.put('success', true);
                recData.put('message', 'File Storage checkbox will be unchecked');
                resultData.add(recData);
            }

            if(!String.isBlank(id)){

                ContentVersion cvUpdate = new ContentVersion();
                cvUpdate.Id = id;
                cvUpdate.Send_File_to_Portal__c = !isDelete;

                toUpdate.add(cvUpdate);	

                recData.put('success', true);
                recData.put('message', 'Checkbox updated');

                resultData.add(recData);

                continue;
            }

            String title       = (String)recData.get('title');
            String fileName    = (String)recData.get('file_name');
            String docUrl      = (String)recData.get('document_url');
            String accountId   = (String)recData.get('Accountid');
            String description = (String)recData.get('description');
            String createdDateStr = (String)recData.get('created_date');
            String sourceType     = (String)recData.get('source_type');
            String category      = (String)recData.get('category');
            
            Datetime date_time;
            
            if(!String.isBlank(createdDateStr)){
                createdDateStr = createdDateStr.replace('T', ' ').replace('Z', '');
                date_time = Datetime.valueOfGmt(createdDateStr);
            }
            

            if(String.isBlank(docUrl) || String.isBlank(fileName)){

                recData.put('success', false);
                recData.put('message', 'Missing document_url or file_name');

                resultData.add(recData);
                continue;
            }

            Blob fileBlob = downloadFile(docUrl);

            if(fileBlob == null){

                recData.put('success', false);
                recData.put('message', 'File download failed');

                resultData.add(recData);
                continue;
            }

            ContentVersion cv = new ContentVersion();

            cv.Title = String.isBlank(title) ? fileName : title;
            cv.PathOnClient = fileName;
            cv.VersionData = fileBlob;
            cv.Description = description;
            cv.IsMajorVersion = true;
            cv.FirstPublishLocationId = accountId;
            cv.Send_File_to_Portal__c = !isDelete;
            cv.Service_Date_Time__c = date_time;
            cv.Source_Type__c          = sourceType;
            cv.Category__c             = category;

            toInsert.add(cv);

            insertIndexMap.put(toInsert.size()-1, recData);
        }

        if(!toInsert.isEmpty()){

            Database.SaveResult[] results = Database.insert(toInsert, false);

            for(Integer i=0;i<results.size();i++){

                Database.SaveResult sr = results[i];

                Map<String,Object> recData = insertIndexMap.get(i);

                if(sr.isSuccess()){

                    recData.put('id', sr.getId());
                    recData.put('success', true);
                    recData.put('message', 'File created');

                }else{

                    String err = sr.getErrors()[0].getMessage();

                    recData.put('success', false);
                    recData.put('message', err);
                }

                resultData.add(recData);
            }
        }

        if(!toUpdate.isEmpty()){
            update toUpdate;
        }
        
        if(!fileRangerCVIds.isEmpty()){
            List<fra__File_Storage__c> fileRangerRecords = [
                SELECT Id, Send_to_Portal__c
                FROM fra__File_Storage__c
                WHERE Id IN :fileRangerCVIds];
            
       for(fra__File_Storage__c fr : fileRangerRecords){
                fr.Send_to_Portal__c = false;
            }

            if(!fileRangerRecords.isEmpty()){
                update fileRangerRecords;
            }
        }

        return resultData;
    }

    private static Blob downloadFile(String url){

        try{

            HttpRequest req = new HttpRequest();
            req.setEndpoint(url);
            req.setMethod('GET');
            req.setTimeout(120000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if(res.getStatusCode() == 200){
                return res.getBodyAsBlob();
            }

            return null;

        }catch(Exception e){

            System.debug('Callout Error: '+e.getMessage());
            return null;
        }
    }
}