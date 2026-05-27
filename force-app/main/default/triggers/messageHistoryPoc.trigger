trigger messageHistoryPoc on sra__Message_History__c (before insert) {
    String signature = '\n\n-- Test Signature';
  /*  
    for(sra__Message_History__c msg : trigger.new){
        // Check if Message Body exists and signature not already added
        if(String.isNotBlank(msg.sra__Message_Body__c) 
           && !msg.sra__Message_Body__c.containsIgnoreCase('-- Test Signature')) {
               
               msg.sra__Message_Body__c += signature;
           }
    }
*/
    
    
}