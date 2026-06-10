public with sharing class SyncController {
    
    @AuraEnabled
    public static void syncAccount(String accountId) {
        
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Account Id is missing.');
        }
        
        List<Account> accList = [
            SELECT Metriport_Patient_Id__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        
        if (accList.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }
        
        Account acc = accList[0];
        
        if (String.isBlank(acc.Metriport_Patient_Id__c)) {
            throw new AuraHandledException('Patient creation incomplete.');
        }
        acc.Last_Refresh_Date__c = System.now();
        update acc;
        
        //Metriport Schdeuler 
        Datetime runTime = System.now().addMinutes(5);   
        String cronExp = runTime.second() + ' ' +
            runTime.minute() + ' ' +
            runTime.hour() + ' ' +
            runTime.day() + ' ' +
            runTime.month() + ' ? ' +
            runTime.year();
        
        System.schedule(
            'SyncMetriport_' + runTime.getTime(),
            cronExp,
            new MetriportScheduler(acc.Metriport_Patient_Id__c)
        );
        
        //Metriport Filter Schduler 
     /*    Datetime runTimes = System.now().addMinutes(6);   
        String cronExps = runTimes.second() + ' ' +
            runTimes.minute() + ' ' +
            runTimes.hour() + ' ' +
            runTimes.day() + ' ' +
            runTimes.month() + ' ? ' +
            runTimes.year();
        
        System.schedule(
            'SyncFilterMetriport_' + runTimes.getTime(),
            cronExps,
            new MetriportFilterScheduler(acc.Metriport_Patient_Id__c)
        ); */

        
        
    }
    
    
    
    @AuraEnabled
    public static void createPatient(Id accountId) {
        if(accountId == null) {
            throw new AuraHandledException('Account Id is null.');
        }
        
        List<Account> accList = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];
        if(accList.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }
        
        Account acc = accList[0];
        Map<Id, String> accToExternalIdMap = new Map<Id, String>();
        accToExternalIdMap.put(acc.Id, acc.Name);
        
        MetriportPatientService.createMetriportPatients(accToExternalIdMap);
    }
    
    @AuraEnabled
    public static void sendPatientData(Id contactId) {
        SendMetriportDataToPortal.sendPatientDataMethod(contactId);
    }

    @AuraEnabled
    public static String sendInsuranceData(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is null.');
        }
        return MemberPlanController.sendAllMemberPlansToThirdParty(accountId);
    }

     @AuraEnabled
    public static void UpdateMemberCheckbox(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is null.');
        }
        SendMetriportDataToPortal.updateSendMemberToPortal(accountId);
    }
    
    @AuraEnabled
    public static void sendFamilyData(Id accountId){
        if (accountId == null) {
            throw new AuraHandledException('Account Id is null.');
        }
        SendMetriportDataToPortal.sendFamilyMemberData(accountId);
    }
    
        @AuraEnabled
        public static void deletePatient(Id accountId) {
    
            if(accountId == null){
                return;
            }
    
            List<Account> accList = [
                SELECT Id, Metriport_Patient_Id__c
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
    
            if(accList.isEmpty()){
                return;
            }
    
            Account acc = accList[0];
    
            if(String.isBlank(acc.Metriport_Patient_Id__c)){
                return;
            }
    
            Map<Id,String> accountIdToMetriportPatientId = new Map<Id,String>();
            accountIdToMetriportPatientId.put(acc.Id, acc.Metriport_Patient_Id__c);
    
            MetriportPatientDeleteService.deleteMetriportPatients(accountIdToMetriportPatientId);
        }
}