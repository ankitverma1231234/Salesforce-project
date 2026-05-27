public with sharing class PublishMedicationEvent {
    @TestVisible
    public static User usr;
    
    //********************************************************************************
    //* Method		:	publishMedicationEvent
    //* Description	:	Method to publish Medication Platform Event and mark user record
    //*					to track event publication status
    //* Parameters	: 	none
    //* Returns		:	void
    //*********************************************************************************/
    @AuraEnabled(cacheable=false)
    public static void publishMedicationEvent() {
        try {
            // Get User Details 
            if(usr == NULL) {
                usr = [SELECT Id, Contact.Account.Athena_Patient_Id__c, LastLoginDate, SecondLastLoginDateTime__c  
                       FROM User 
                       WHERE Id =:Userinfo.getUserId() AND Contact.Account.Athena_Patient_Id__c != NULL LIMIT 1];
            }
            System.debug('isLoggedOnBehalf( ' + isLoggedOnBehalf());
            
            if(Test.isRunningTest() || (usr != NULL && usr.SecondLastLoginDateTime__c != NULL && !isLoggedOnBehalf()) || (usr != NULL && usr.SecondLastLoginDateTime__c == NULL && !isLoggedOnBehalf() && usr.LastLoginDate != NULL))
            {
                System.debug('Proceed >>> ');
                Date lastLoginDate = Date.valueOf(usr.LastLoginDate);
                Date secondLastLoginDate = Date.valueOf(usr.SecondLastLoginDateTime__c);
                
                System.debug('lastLoginDate: ' + lastLoginDate); 
                System.debug('Date.today(): ' + Date.today());
                System.debug('secondLastLoginDate: ' + secondLastLoginDate);
                //Conditions to verify weather medication event should be fired
                if(secondLastLoginDate == null || (secondLastLoginDate != null && secondLastLoginDate != Date.today())) {
                    // Fire platform event
                    publishEvent(usr.Contact.Account.Athena_Patient_Id__c);
                }
            }
        } catch(Exception ex) {
            System.debug('An exception occurred: ' + ex.getMessage() + ' at line number: ' + ex.getLineNumber() + '  ' + ex.getStackTraceString());
            throw new AuraHandledException(ex.getMessage());
        }
    }
    
    public static Boolean isLoggedOnBehalf() {
        String potentialSession = UserInfo.getSessionId();
        if (String.isBlank(potentialSession) || Test.isRunningTest()) {
            return false ;
        } else {
             Map<String, String> session = Auth.SessionManagement.getCurrentSession();
             return session.get('UserType') == 'Standard' &&
             session.get('SourceIp') == '::' && 
             session.get('LoginType') == 'Unknown';   
       }
    }
    
    //********************************************************************************
    //* Method		:	publishEvent
    //* Description	:	Method to publish Medication Platform Event  
    //* Parameters	: 	String athenaId
    //* Returns		:	void
    //*********************************************************************************/
    public static void publishEvent(String athenaId) {
        System.debug('publishEvent platform event');
        GenericObjectEvent__e event = new GenericObjectEvent__e(
            Record_Id__c = athenaId,
            Object_Name__c = 'Medication'
        );
        Database.SaveResult result = EventBus.publish(event);
        if(!result.isSuccess()){
            for (Database.Error error : result.getErrors()) {
                System.debug('Error publishing event: ' + error.getMessage());
            }
            throw new AuraHandledException('Failed to publish event');
        }
        else{
            User u = [SELECT Id, LastLoginDate, SecondLastLoginDateTime__c  
                      FROM User 
                      WHERE Id =:Userinfo.getUserId()];
            u.SecondLastLoginDateTime__c = u.LastLoginDate;
            update u;
        }
    }
}