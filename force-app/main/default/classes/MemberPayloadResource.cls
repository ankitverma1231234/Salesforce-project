@RestResource(urlMapping='/member-payload/*')
global without sharing class MemberPayloadResource{

    global class ApiResponse {
        public Boolean success;
        public String  message;
        public String  stagingId;

        public ApiResponse(Boolean success, String message, String stagingId) {
            this.success   = success;
            this.message   = message;
            this.stagingId = stagingId;
        }
    }

   
    @HttpPost
    global static void handlePost() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        Member_Payload__c staging = new Member_Payload__c();

        try {
            String jsonBody = req.requestBody != null
                ? req.requestBody.toString()
                : null;

            if (String.isBlank(jsonBody)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(
                    JSON.serialize(new ApiResponse(false, 'Request body is empty.', null))
                );
                return;
            }

            Map<String, Object> payload;
            try {
                payload = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
            } catch (Exception parseEx) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(
                    JSON.serialize(new ApiResponse(false, 'Invalid JSON: ' + parseEx.getMessage(), null))
                );
                return;
            }

            String accountId = (String) payload.get('accountId');
            Account primaryAcc = null;

            if (String.isNotBlank(accountId)) {
                List<Account> accList = [
                    SELECT Id, Name
                    FROM Account
                    WHERE Id = :accountId
                    LIMIT 1
                ];
                if (!accList.isEmpty()) {
                    primaryAcc = accList[0];
                }
            }

            Integer memberCount = 0;
            List<Object> membersArray = (List<Object>) payload.get('members');
            if (membersArray != null) {
                memberCount = membersArray.size();
            }

           
            staging.Status__c       = 'Pending';
            staging.Member_Count__c = string.valueof(memberCount);
            staging.Payload_JSON__c = jsonBody;

            if (primaryAcc != null) {
                staging.Primary_Account__c = primaryAcc.Id;
            }

            insert staging;

            res.statusCode   = 200;
            res.responseBody = Blob.valueOf(
                JSON.serialize(new ApiResponse(true, 'Payload received and stored successfully.', staging.Id))
            );

        } catch (Exception e) {
            String errorMsg = e.getMessage() + ' | Line: ' + e.getLineNumber() + ' | Stack: ' + e.getStackTraceString();

            if (staging.Id != null) {
                staging.Status__c        = 'Failed';
                staging.Error_Message__c = errorMsg;
                update staging;
            } else {
                try {
                    Member_Payload__c errorRecord = new Member_Payload__c(
                        Status__c        = 'Failed',
                        Error_Message__c = errorMsg
                    );
                    insert errorRecord;
                } catch (Exception innerEx) {
                    System.debug('Could not insert error staging record: ' + innerEx.getMessage());
                }
            }

            res.statusCode   = 500;
            res.responseBody = Blob.valueOf(
                JSON.serialize(new ApiResponse(false, 'Error: ' + e.getMessage(), null))
            );
        }
    }
}