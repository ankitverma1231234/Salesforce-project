public class sendDatatoWebPageHandler {

    public static void sendingAPIdata(List <CareObservation> cnew){
        
        TriggerSettings__c ts = TriggerSettings__c.getInstance();
        if (ts == null || !ts.Care_Observation_Checkbox__c  ){
            return ;
        }
        Set<Id> recIds = new Set<Id>();

    for(CareObservation co : cnew){
        if(co.Category == 'Vital-Signs')
        recIds.add(co.Id); 
    }

    if(!recIds.isEmpty()){
        VitalAPIHandler.sendData(recIds);
    }
    }
}