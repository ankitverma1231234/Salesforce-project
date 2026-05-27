trigger MapRelatedObject on sra__Message_History__c (before insert) {

    System.debug(' TRIGGER START: MapRelatedObject BEFORE INSERT');

    
    Set<Id> accountIds = new Set<Id>();
    Set<Id> contactIds = new Set<Id>();
    Set<Id> leadIds = new Set<Id>();
    Set<Id> oppIds = new Set<Id>();

    
    for (sra__Message_History__c msg : Trigger.new) {
        System.debug('Processing Message Record: ' + msg);

        if (msg.sra__Type__c == 'Inbound' 
            && String.isNotBlank(msg.sra__Related_Object_Id__c)) {

            String relIdStr = String.valueOf(msg.sra__Related_Object_Id__c);
            String prefix = relIdStr.substring(0, 3);

            System.debug('Related Object ID: ' + relIdStr + ' | Prefix: ' + prefix);

            if (prefix == '001') {
                accountIds.add((Id)relIdStr);
                System.debug('Detected Account ID → ' + relIdStr);
            }
            else if (prefix == '003') {
                contactIds.add((Id)relIdStr);
                System.debug('Detected Contact ID → ' + relIdStr);
            }
            else if (prefix == '00Q') {
                leadIds.add((Id)relIdStr);
                System.debug('Detected Lead ID → ' + relIdStr);
            }
            else if (prefix == '006') {
                oppIds.add((Id)relIdStr);
                System.debug('Detected Opportunity ID → ' + relIdStr);
            }
            else {
                System.debug(' WARNING: Unknown prefix, no mapping performed.');
            }
        }
    }

    
    System.debug('Querying related records...');

    Map<Id, Account> accounts = accountIds.isEmpty() 
        ? new Map<Id, Account>() 
        : new Map<Id, Account>([
            SELECT Id FROM Account WHERE Id IN :accountIds
        ]);

    Map<Id, Contact> contacts = contactIds.isEmpty()
        ? new Map<Id, Contact>()
        : new Map<Id, Contact>([
            SELECT Id FROM Contact WHERE Id IN :contactIds
        ]);

    Map<Id, Lead> leads = leadIds.isEmpty()
        ? new Map<Id, Lead>()
        : new Map<Id, Lead>([
            SELECT Id FROM Lead WHERE Id IN :leadIds
        ]);

    Map<Id, Opportunity> opps = oppIds.isEmpty()
        ? new Map<Id, Opportunity>()
        : new Map<Id, Opportunity>([
            SELECT Id FROM Opportunity WHERE Id IN :oppIds
        ]);

    System.debug('Accounts Found: ' + accounts.keySet());
    System.debug('Contacts Found: ' + contacts.keySet());
    System.debug('Leads Found: ' + leads.keySet());
    System.debug('Opportunities Found: ' + opps.keySet());

    
    for (sra__Message_History__c msg : Trigger.new) {
        if (msg.sra__Type__c == 'Inbound' 
            && String.isNotBlank(msg.sra__Related_Object_Id__c)) {

            String relIdStr = String.valueOf(msg.sra__Related_Object_Id__c);
            String prefix = relIdStr.substring(0, 3);
            Id relId = (Id)relIdStr;

            System.debug('Mapping lookup for ID: ' + relId);

            if (prefix == '001' && accounts.containsKey(relId)) {
                msg.sra__Account__c = relId;
                System.debug(' Mapped to Account: ' + relId);
            }
            else if (prefix == '003' && contacts.containsKey(relId)) {
                msg.sra__Contact__c = relId;
                System.debug(' Mapped to Contact: ' + relId);
            }
            else if (prefix == '00Q' && leads.containsKey(relId)) {
                msg.sra__Lead__c = relId;
                System.debug(' Mapped to Lead: ' + relId);
            }
            else if (prefix == '006' && opps.containsKey(relId)) {
                msg.sra__Opportunity__c = relId;
                System.debug(' Mapped to Opportunity: ' + relId);
            }
            else {
                System.debug(' No matching record found. Lookup not mapped.');
            }
        }
    }

    System.debug(' TRIGGER END: MapRelatedObject ');
}