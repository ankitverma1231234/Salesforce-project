@RestResource(urlMapping='/Casechatterportal/V1/*')
global without sharing class CaseMedicalChatterCrate {
    
    @HttpPost
    global static ResponseWrapper receiveData() {
        
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        ResponseWrapper response = new ResponseWrapper();
        
        res.addHeader('Access-Control-Allow-Origin', '*');
        res.addHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
        res.addHeader('Content-Type', 'application/json');
        
        try {
            Map<String, Object> body =
                (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            
            if (body.containsKey('messages')) {
                
                List<Case> createdCases =
                    createCases((List<Object>) body.get('messages'));
                
                if (!createdCases.isEmpty()) {
                    Case c = createdCases[0];
                    response.message = 'Case created successfully. Files are being processed.';
                    response.caseId = c.Id;
                    response.caseNumber = c.CaseNumber;
                    response.success = true;
                }
            }
            
            else if (body.containsKey('conversations')) {
                
                createCaseFeedItems((List<Object>) body.get('conversations'));
                response.message = 'Case Comment created successfully';
                response.success = true;
            }
            else {
                res.statusCode = 400;
                response.message = 'Invalid payload structure';
                response.success = false;
            }
            
        } catch (Exception ex) {
            res.statusCode = 500;
            response.message = ex.getMessage();
            response.success = false;
        }
        return response;
    }
    
    // CASE CREATE
    private static List<Case> createCases(List<Object> messages) {
        List<Case> casesToInsert = new List<Case>();
        List<FileAttachmentWrapper> fileWrappers = new List<FileAttachmentWrapper>();
        User automatedProcessUser = [
        SELECT Id 
        FROM User 
        WHERE Name = 'Automated Process' 
        AND UserType = 'AutomatedProcess' 
        LIMIT 1];
        
        for (Object obj : messages) {
            Map<String, Object> msg = (Map<String, Object>) obj;
            
            if (msg.containsKey('Id') && msg.get('Id') != null) {
                continue;
            }
            
            Case c = new Case();
            c.Subject = (String) msg.get('Subject');
            c.Description = (String) msg.get('Description');
            c.Status = (String) msg.get('Status');
            c.Priority = (String) msg.get('Priority');
            c.Origin = (String) msg.get('Origin');
            c.Reason = (String) msg.get('Reason');
            c.Type = (String) msg.get('Type');
            c.SuppliedEmail = (String) msg.get('SuppliedEmail');
            c.SuppliedPhone = (String) msg.get('SuppliedPhone');
            c.CreatedById   = automatedProcessUser.Id;
            c.LastModifiedById = automatedProcessUser.Id;
            c.OwnerId =  automatedProcessUser.Id;
            if (msg.containsKey('AccountId') && msg.get('AccountId') != null 
                && String.isNotBlank(String.valueOf(msg.get('AccountId')))) {
                    try {
                        c.AccountId = (Id) msg.get('AccountId');
                    } catch (Exception e) {
                        System.debug('Invalid AccountId: ' + msg.get('AccountId'));
                    }
                }
            if (msg.containsKey('ContactId') && msg.get('ContactId') != null 
                && String.isNotBlank(String.valueOf(msg.get('ContactId')))) {
                    try {
                        c.ContactId = (Id) msg.get('ContactId');
                    } catch (Exception e) {
                        System.debug('Invalid ContactId: ' + msg.get('ContactId'));
                    }
                }
            
            casesToInsert.add(c);
            
            if (msg.containsKey('Attachment') && msg.get('Attachment') != null) {
                Map<String, Object> attachmentInfo = (Map<String, Object>) msg.get('Attachment');
                
                String fileUrl = (String) attachmentInfo.get('url');
                String filename = (String) attachmentInfo.get('filename');
                
                if (String.isNotBlank(fileUrl) && String.isNotBlank(filename)) {
                    FileAttachmentWrapper wrapper = new FileAttachmentWrapper();
                    wrapper.caseIndex = casesToInsert.size() - 1;
                    wrapper.fileUrl = fileUrl;
                    wrapper.filename = filename;
                    
                    fileWrappers.add(wrapper);
                }
            }
        }
        
        if (casesToInsert.isEmpty()) {
             return new List<Case>();           
        }
        
        insert casesToInsert;
        system.debug('Insertcase>>>'+casesToInsert);
        
        if (!fileWrappers.isEmpty()) {
            List<FileAttachmentWrapper> wrappersWithCaseIds = new List<FileAttachmentWrapper>();
            
            for (FileAttachmentWrapper wrapper : fileWrappers) {
                wrapper.caseId = casesToInsert[wrapper.caseIndex].Id;
                wrappersWithCaseIds.add(wrapper);
            }
            if (!Test.isRunningTest()) {
                System.enqueueJob(
                    new FileAttachmentQueueable(wrappersWithCaseIds)
                );
}
        }
        
        return [
            SELECT Id, CaseNumber
            FROM Case
            WHERE Id IN :casesToInsert
            ORDER BY CreatedDate ASC];
    }
    
    // Create a CaseComment
    private static void createCaseFeedItems(List<Object> conversations) {
        List<CaseComment> commentsToInsert = new List<CaseComment>();
        
        for (Object obj : conversations) {
            Map<String, Object> convo = (Map<String, Object>) obj;
            Id caseId = Id.valueOf(String.valueOf(convo.get('case_message_id')));
            String messageBody = (String) convo.get('message_body');
            if (!String.isBlank(messageBody)) {
                CaseComment cc = new CaseComment();
                cc.ParentId = caseId;
                cc.CommentBody = messageBody;
                cc.IsPublished = true;
                commentsToInsert.add(cc);
            }
            Map<String, Object> attachment =
                (Map<String, Object>) convo.get('attachment');
            
            if (attachment != null) {
                String fileUrl  = (String) attachment.get('url');
                String fileName = (String) attachment.get('filename');
                
                if (!String.isBlank(fileUrl) && !String.isBlank(fileName)) {
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(
                            new CaseFeedFileQueueable(caseId, fileUrl, fileName)
                        );
                    }
                }
            }
        }
        
        
        if (!commentsToInsert.isEmpty()) {
            insert commentsToInsert;
        }
        
    }
    
    public class FileAttachmentWrapper {
        public Id caseId;
        public Integer caseIndex;
        public String fileUrl;
        public String filename;
        public String noteTitle;     
        public String noteContent; 
    }
    global class ResponseWrapper {
        public String message;
        public Id caseId;
        public String caseNumber;
        public Boolean success;
    }
}