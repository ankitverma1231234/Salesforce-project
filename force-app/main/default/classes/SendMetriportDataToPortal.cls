public class SendMetriportDataToPortal {
    
    public static void sendPatientDataMethod(Id contactId) {
        if (contactId == null) {
            System.debug('No contact Id provided');
            return;
        }
        sendLiteDataFuture(contactId);
    }
    
    @future(callout=true)
    private static void sendLiteDataFuture(Id contactId) {
        try {
            BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
            if (apiConfig == null || String.isBlank(apiConfig.Api_key_2__c)) {
                System.debug(LoggingLevel.ERROR, 'Api_key_2__c not configured');
                return;
            }
            
            String endpoint = apiConfig.Api_key_2__c;
            
            Map<String, Object> payload = buildLitePayload(contactId);
            if (payload.isEmpty()) {
                System.debug('No data found for contact: ' + contactId);
                return;
            }
            Contact c = [SELECT AccountId FROM Contact WHERE Id = :contactId LIMIT 1];
            preparePublicLinks(c.AccountId, contactId);
            
            HttpResponse response = sendHttpRequest(endpoint, payload);
            if (response != null) {
                System.debug('Lite API Status: ' + response.getStatusCode());
                System.debug('Lite API Body: ' + response.getBody());
                if (response.getStatusCode() == 200) {
                    updateSendMemberToPortal(c.AccountId);
                    System.debug('Send_Member_to_portal__c updated successfully');
                }
            }
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                         'Lite API error: ' + ex.getMessage() +
                         '\nStack: ' + ex.getStackTraceString());
        }
    }
    
    public static void updateSendMemberToPortal(Id accountId) {
        if (accountId == null) return;
        try {
            update new Account(Id = accountId, Send_Member_to_portal__c = true);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'updateSendMemberToPortal: ' + ex.getMessage());
        }
    }
    
    private static Map<String, Object> buildLitePayload(Id contactId) {
        Map<String, Object> payload = new Map<String, Object>();
        try {
            Contact c = [
                SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, HomePhone,
                AccountId, Account.Name, Account.IsPersonAccount,
                Account.Date_of_Birth__pc, Account.Sign_up_date__pc,
                Account.Work_Phone__pc, Account.Height_in_inches__pc,
                Account.Weight_in_pounds__pc, Account.Consent_to_Call__pc,
                Account.Consent_to_Text__pc, Account.Renewal_Date__pc,
                Account.Preferred_Name__pc, Account.Salutation, Account.Suffix,
                Account.Occupation__pc, Account.Marital_Status__pc, Account.Family_Head__c,
                Account.Biological_Sex_at_Birth__c,
                Account.Sexual_Orientation__pc, Account.Race__pc,Account.Patient_Summary__c,
                Account.PersonMailingStreet, Account.PersonMailingCity,Account.PersonOtherStreet, Account.PersonMailingState, Account.PersonMailingPostalCode, Account.PersonMailingCountry,
                Account.BillingStreet,Account.BillingCity,Account.BillingState,Account.BillingPostalCode,Account.BillingCountry,Account.Additional_Email__pc,Account.PersonGenderIdentity,Account.Ethnicity__pc,
                Account.Living_Situation__pc,Account.Fax,Account.Preferred_Method_of_Contact__pc,Account.Maiden_Name__pc
                FROM Contact
                WHERE Id = :contactId
                AND Account.IsPersonAccount = true
                LIMIT 1
            ];
            
            payload.put('contactId', String.valueOf(contactId));
            payload.put('basic_details', getBasicDetails(c));
            payload.put('allergies', getAllergies(c.AccountId));
            payload.put('medications', getMedications(c.AccountId));
            payload.put('medical_history', getMedicalHistory(c.AccountId));
            payload.put('surgical_history', getSurgicalHistory(c.AccountId));
            payload.put('personal_contacts', getPersonalContacts(c.AccountId));
            payload.put('healthcare_facilities', getHealthcareFacilities(c.AccountId));
            payload.put('healthcare_professionals', getHealthcareProfessionals(c.AccountId));
            payload.put('insurance_details', getInsuranceDetails(c.AccountId));
            payload.put('documents', getDocuments(c.AccountId, c.Id));
            
        } catch (Exception ex) {
            System.debug('Error building lite payload: ' + ex.getMessage());
        }
        return payload;
    }
    
    private static String safeString(Object val) {
        return val == null ? '' : String.valueOf(val);
    }
    
    private static List<Map<String, Object>> getBasicDetails(Contact c) {
        List<Map<String, Object>> basicDetails = new List<Map<String, Object>>();
        Map<String, Object> data = new Map<String, Object>();
        
        data.put('id', safeString(c.Id));
        data.put('accountId', safeString(c.AccountId));
        data.put('is_head', c.Account != null ? c.Account.Family_Head__c : false);
        data.put('contactId', safeString(c.Id));
        data.put('firstName', safeString(c.FirstName));
        data.put('lastName', safeString(c.LastName));
        data.put('email', safeString(c.Email));
        data.put('phone', safeString(c.Phone));
        data.put('mobilePhone', safeString(c.MobilePhone));
        data.put('homePhone', safeString(c.HomePhone));
        
        data.put('accountName', safeString(c.Account.Name));
        data.put('preferredName', safeString(c.Account.Preferred_Name__pc));
        data.put('salutation', safeString(c.Account.Salutation));
        data.put('suffix', safeString(c.Account.Suffix));
        data.put('dateOfBirth', c.Account.Date_of_Birth__pc != null ? c.Account.Date_of_Birth__pc : null);
        data.put('signUpDate', c.Account.Sign_up_date__pc != null ? formatDateTime(c.Account.Sign_up_date__pc) : null);
        data.put('workPhone', safeString(c.Account.Work_Phone__pc));
        data.put('height', c.Account.Height_in_inches__pc != null ? String.valueOf(c.Account.Height_in_inches__pc) : null);
        data.put('weight', c.Account.Weight_in_pounds__pc != null ? String.valueOf(c.Account.Weight_in_pounds__pc) : null);
        data.put('okToCall', c.Account.Consent_to_Call__pc != null ? c.Account.Consent_to_Call__pc : false);
        data.put('okToText', c.Account.Consent_to_Text__pc != null ? c.Account.Consent_to_Text__pc : false);
        data.put('renewalDate', c.Account.Renewal_Date__pc != null ? formatDateTime(c.Account.Renewal_Date__pc) : null);
        data.put('occupation', safeString(c.Account.Occupation__pc));
        data.put('maritalStatus', safeString(c.Account.Marital_Status__pc));
        data.put('biologicalSexAtBirth', safeString(c.Account.Biological_Sex_at_Birth__c));
        data.put('sexualOrientation', safeString(c.Account.Sexual_Orientation__pc));
        data.put('race', safeString(c.Account.Race__pc));
        data.put('summary',safeString(c.Account.Patient_Summary__c));
        data.put('additionalEmail', safeString(c.Account.Additional_Email__pc));
        data.put('genderIdentity', safeString(c.Account.PersonGenderIdentity));
        data.put('ethnicity', safeString(c.Account.Ethnicity__pc));
        data.put('livingSituation', safeString(c.Account.Living_Situation__pc));
        
        data.put('fax', safeString(c.Account.Fax));
        data.put('preferredContactMethod', safeString(c.Account.Preferred_Method_of_Contact__pc));
        data.put('maidenName', safeString(c.Account.Maiden_Name__pc));
        
        /* Mailing Address */
        Map<String, Object> mailingAddress = new Map<String, Object>();
        mailingAddress.put('street', safeString(c.Account.PersonMailingStreet));
        mailingAddress.put('city', safeString(c.Account.PersonMailingCity));
        mailingAddress.put('state', safeString(c.Account.PersonMailingState));
        mailingAddress.put('zipCode', safeString(c.Account.PersonMailingPostalCode));
        mailingAddress.put('country', safeString(c.Account.PersonMailingCountry));
        
        data.put('mailingAddress', mailingAddress);
        
        /* Other Address */
        Map<String, Object> otherAddress = new Map<String, Object>();
        otherAddress.put('street', safeString(c.Account.BillingStreet));
        otherAddress.put('city', safeString(c.Account.BillingCity));
        otherAddress.put('state', safeString(c.Account.BillingState));
        otherAddress.put('zipCode', safeString(c.Account.BillingPostalCode));
        otherAddress.put('country', safeString(c.Account.BillingCountry));
        
        data.put('otherAddress', otherAddress);
        
        basicDetails.add(data);
        return basicDetails;
    }
    
    // Send Family Data to portal
    public static void sendFamilyMemberData(Id authorizedAccountId) {
        if (authorizedAccountId == null) return;
        if (System.isFuture() || System.isBatch()) {
            processFamilySync(authorizedAccountId);
            return;
        }
        sendFamilyFuture(authorizedAccountId);
    }
    
    @future(callout=true)
    public static void sendFamilyFuture(Id authorizedAccountId) {
        processFamilySync(authorizedAccountId);
    }
    
    public static void processFamilySync(Id parentAccountId) {
    BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
    if (apiConfig == null || String.isBlank(apiConfig.Api_key_2__c)) {
        System.debug(LoggingLevel.ERROR, 'Api_key_2__c not configured');
        return;
    }
    String endpoint = apiConfig.Api_key_2__c;

    List<Account_Head_Relationship__c> junctionRecords = [
        SELECT Id,
               Authorized_Account_Access__c,
               Authorized_Account_Access__r.Id,
               Authorized_Account_Access__r.FirstName,
               Authorized_Account_Access__r.LastName,
               Authorized_Account_Access__r.Name,
               Authorized_Account_Access__r.PersonContactId,
               Relationship__c,
               Portal_Access_Status__c,
               Member_Account__c,
               Member_Account__r.Id,
               Member_Account__r.FirstName,
               Member_Account__r.LastName,
               Member_Account__r.Family_Head__c,
               Member_Account__r.Name,
               Member_Account__r.PersonContactId,
               Request_Access__c,
               Give_Access__c
              FROM Account_Head_Relationship__c
             WHERE Member_Account__c = :parentAccountId  
            AND Member_Account__c != null
            AND Authorized_Account_Access__c != null];

    if (junctionRecords.isEmpty()) return;

    Account headAccount = junctionRecords[0].Member_Account__r;

    Map<String, Object> parentMap = new Map<String, Object>();
    parentMap.put('accountId',  String.valueOf(headAccount.Id));
    parentMap.put('first_name', headAccount.FirstName != null ? headAccount.FirstName : '');
    parentMap.put('last_name',  headAccount.LastName  != null ? headAccount.LastName  : '');
    parentMap.put('id',         headAccount.PersonContactId != null ? String.valueOf(headAccount.PersonContactId) : null);
    parentMap.put('is_head',    headAccount.Family_Head__c);

    Map<Id, Map<String, Object>> childrenByAccountId = new Map<Id, Map<String, Object>>();

    for (Account_Head_Relationship__c jr : junctionRecords) {
        if (jr.Authorized_Account_Access__r == null) continue;

        Id childAccId = jr.Authorized_Account_Access__r.Id;
        if (childrenByAccountId.containsKey(childAccId)) continue; 

        Map<String, Object> childMap = new Map<String, Object>();
        childMap.put('accountId',       String.valueOf(childAccId));
        childMap.put('account_headrelationshipid', String.valueOf(jr.Id));
        childMap.put('name',            jr.Authorized_Account_Access__r.Name != null ? jr.Authorized_Account_Access__r.Name: '');
        childMap.put('relationship',    jr.Relationship__c != null ? jr.Relationship__c : '');
        childMap.put('portal_status',   jr.Portal_Access_Status__c != null ? jr.Portal_Access_Status__c : '');
        childMap.put('id',              jr.Authorized_Account_Access__r.PersonContactId != null ? String.valueOf(jr.Authorized_Account_Access__r.PersonContactId) : null);
        childMap.put('request_access',  jr.Request_Access__c);
        childMap.put('give_access',     jr.Give_Access__c);
        childMap.put('headAccountName', headAccount.Name != null ? headAccount.Name : '');
        childMap.put('is_delete',       false);
        childrenByAccountId.put(childAccId, childMap);
    }

    Map<String, Object> payload = new Map<String, Object>();
    payload.put('is_template', false);
    payload.put('contactId', headAccount.PersonContactId != null ? String.valueOf(headAccount.PersonContactId) : null);
    payload.put('parent',    parentMap);
    payload.put('children',  childrenByAccountId.values()); 

    try {
        HttpResponse res = sendHttpRequest(endpoint, payload);
        if (res != null) {
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                System.debug('Family data sent - Parent Account: ' + parentAccountId);
            } else {
                System.debug(LoggingLevel.ERROR, 'Family send failed: ' + res.getStatusCode() + ' ' + res.getBody());
                System.debug(LoggingLevel.ERROR, 'Request Body: ' + JSON.serialize(payload));
            }
        }
    } catch (Exception ex) {
        System.debug(LoggingLevel.ERROR, 'Family callout error: ' + ex.getMessage());
    }
}

    private static List<Map<String, Object>> getAllergies(Id contactId) {
        List<Map<String, Object>> allergies = new List<Map<String, Object>>();
        for (AllergyIntolerance a : [
            SELECT Id,Name, Allergy_Name__c, Severity,Status, OnsetStartDateTime,OnsetEndDateTime, Note__c,Generic__c,Combine_allergy_and_Generic__c
            FROM AllergyIntolerance
            WHERE PatientId = :contactId
        ]) {
            Map<String, Object> data = new Map<String, Object>();
            data.put('id', safeString(a.Id));
            data.put('name', safeString(a.Combine_allergy_and_Generic__c));
            data.put('severity', safeString(a.Severity));
            data.put('reaction', safeString(a.Allergy_Name__c));
            data.put('onsetDate', a.OnsetStartDateTime != null ? formatDateTime(a.OnsetStartDateTime) : null);
            data.put('note', safeString(a.Note__c));
            data.put('generic', safeString(a.Generic__c));
            data.put('status', safeString(a.Status));
            
            allergies.add(data);
        }
        return allergies;
    }
    
    private static List<Map<String, Object>> getMedications(Id accountId) {
        List<Map<String, Object>> medications = new List<Map<String, Object>>();
        for (MedicationStatement m : [
            SELECT Id, MedicationId, Dose__c, Frequency__c, Reason__c,
            StartDateTime, EndDateTime, Status, Comments__c, Medication_Name__c
            FROM MedicationStatement
            WHERE PatientId = :accountId
        ]) {
            Map<String, Object> data = new Map<String, Object>();
            data.put('id', safeString(m.Id));
            data.put('medicationId', safeString(m.MedicationId));
            data.put('medication', safeString(m.Medication_Name__c));
            data.put('dosage', safeString(m.Dose__c));
            data.put('frequency', safeString(m.Frequency__c));
            data.put('reason', safeString(m.Reason__c));
            data.put('startDate', m.StartDateTime != null ? formatDateTime(m.StartDateTime) : null);
            data.put('endDate', m.EndDateTime != null ? formatDateTime(m.EndDateTime) : null);
            data.put('status', safeString(m.Status));
            data.put('notes', safeString(m.Comments__c));
            
            medications.add(data);
        }
        return medications;
    }
    
    private static List<Map<String, Object>> getMedicalHistory(Id contactId) {
        List<Map<String, Object>> history = new List<Map<String, Object>>();
        for (HealthCondition m : [
            SELECT Id, ProblemName, ProblemDescription, OnsetStartDateTime,ConditionStatus
            FROM HealthCondition
            WHERE PatientId = :contactId
        ]) {
            Map<String, Object> data = new Map<String, Object>();
            data.put('id', safeString(m.Id));
            data.put('medicalProblem', safeString(m.ProblemName));
            data.put('note', safeString(m.ProblemDescription));
            data.put('onsetDate', m.OnsetStartDateTime != null ? formatDateTime(m.OnsetStartDateTime) : null);
            data.put('cancerType', safeString(m.ProblemName));
            data.put('status', safeString(m.ConditionStatus));
            history.add(data);
        }
        return history;
    }
    
    private static List<Map<String, Object>> getSurgicalHistory(Id contactId) {
        List<Map<String, Object>> surgeries = new List<Map<String, Object>>();
        for (HealthCareProcedure s : [
            SELECT Id, Surgery_Name__c, EffectiveDate, Note__c,Status__c
            FROM HealthCareProcedure
            WHERE Patient__c = :contactId
        ]) {
            Map<String, Object> data = new Map<String, Object>();
            data.put('id', safeString(s.Id));
            data.put('name', safeString(s.Surgery_Name__c));
            data.put('surgeryDate', s.EffectiveDate != null ? formatDateTime(s.EffectiveDate) : null);
            data.put('note', safeString(s.Note__c));
            data.put('status', safeString(s.Status__c));
            
            surgeries.add(data);
        }
        return surgeries;
    }
    
    // personal Contact
    private static List<Map<String, Object>> getPersonalContacts(Id accountId) {
        List<Map<String, Object>> contacts = new List<Map<String, Object>>();
        try {
            List<Contact> records = [
                SELECT Id, FirstName, AccountId, LastName, Email, MobilePhone, HomePhone, 
                Emergency_Contact_Relationship__c, MailingStreet, MailingCity, Account__c,ADT_Contact__c,Authorized_Representative__c,
                MailingState, MailingPostalCode, MailingCountry, Description, Emergency_Contact__c, 
                Is_PHI_Authorized__c, Is_Healthcare_Proxy__c, CreatedDate, LastModifiedDate
                FROM Contact
                WHERE Account__c = :accountId  ORDER BY CreatedDate DESC
            ];            
            for (Contact record : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id', record.Id != null ? record.Id : '');
                data.put('firstName', record.FirstName != null ? record.FirstName : '');
                data.put('lastName', record.LastName != null ? record.LastName : '');
                data.put('relationship', record.Emergency_Contact_Relationship__c != null ? record.Emergency_Contact_Relationship__c : '');
                data.put('mobilePhone', record.MobilePhone != null ? record.MobilePhone : '');
                data.put('homePhone', record.HomePhone != null ? record.HomePhone : '');
                data.put('email', record.Email != null ? record.Email : '');
                data.put('adt_contact', record.ADT_Contact__c != null ? record.ADT_Contact__c : false);
                data.put('authorized_representative', record.Authorized_Representative__c != null ? record.Authorized_Representative__c : false);
                
                Map<String, Object> address = new Map<String, Object>();
                address.put('street', record.MailingStreet != null ? record.MailingStreet : '');
                address.put('city', record.MailingCity != null ? record.MailingCity : '');
                address.put('state', record.MailingState != null ? record.MailingState : '');
                address.put('zipCode', record.MailingPostalCode != null ? record.MailingPostalCode : '');
                address.put('country', record.MailingCountry != null ? record.MailingCountry : '');
                data.put('address', address);
                
                data.put('emergencyContact', record.Emergency_Contact__c != null ? record.Emergency_Contact__c : false);
                data.put('authorizedToDisclose', record.Is_PHI_Authorized__c != null ? record.Is_PHI_Authorized__c : false);
                data.put('healthcareSurrogate', record.Is_Healthcare_Proxy__c != null ? record.Is_Healthcare_Proxy__c : false);
                data.put('notes', record.Description != null ? record.Description : '');
                data.put('accountId', record.Account__c != null ? record.Account__c : '');
                contacts.add(data);
            }
        } catch (Exception ex) {
            System.debug('Error getting personal contacts: ' + ex.getMessage());
        }
        return contacts;
    }
    
    public static List<Map<String, Object>> getHealthcareFacilities(Id accountId) {
        List<Map<String, Object>> facilities = new List<Map<String, Object>>();
        try {
            List<HealthcareFacility> records = [
                SELECT Id, Name, AccountId, Phone__c, Email__c, Facility_type__c, Fax_Number__c, 
                Website__c, Mailing_Address__c, CreatedDate, LastModifiedDate
                FROM HealthcareFacility
                WHERE AccountId = :accountId ORDER BY CreatedDate DESC];   
            
            for (HealthcareFacility record : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id', record.Id != null ? record.Id : '');
                data.put('facilityName', record.Name != null ? record.Name : '');
                data.put('facilityType', record.Facility_type__c != null ? record.Facility_type__c : '');
                data.put('phoneNumber', record.Phone__c != null ? record.Phone__c : '');
                data.put('faxNumber', record.Fax_Number__c != null ? record.Fax_Number__c : '');
                data.put('website', record.Website__c != null ? record.Website__c : '');
                data.put('accountId', accountId);
                data.put('email', record.Email__c != null ? record.Email__c : '');                
                Map<String, Object> address = new Map<String, Object>();
                if (record.Mailing_Address__c != null) {
                    address.put('street', record.Mailing_Address__c.getStreet() != null ? record.Mailing_Address__c.getStreet() : '');
                    address.put('city', record.Mailing_Address__c.getCity() != null ? record.Mailing_Address__c.getCity() : '');
                    address.put('state', record.Mailing_Address__c.getState() != null ? record.Mailing_Address__c.getState() : '');
                    address.put('zipCode', record.Mailing_Address__c.getPostalCode() != null ? record.Mailing_Address__c.getPostalCode() : '');
                    address.put('country', record.Mailing_Address__c.getCountry() != null ? record.Mailing_Address__c.getCountry() : '');
                }
                data.put('address', address);
                facilities.add(data);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting healthcare facilities: ' + e.getMessage() + '\nStack: ' + e.getStackTraceString());
        }
        return facilities;
    }    
    
    public static List<Map<String, Object>> getHealthcareProfessionals(Id accountId) {
        List<Map<String, Object>> professionals = new List<Map<String, Object>>();
        try {
            List<HealthcarePractitionerFacility> records = [
                SELECT Id, Name, AccountId, PractitionerId, Fax_Number__c, Website__c, 
                Practitioner.Name, Phone__c, Email__c, Specialty__c, EffectiveFrom, 
                EffectiveTo, Address__c, CreatedDate, LastModifiedDate
                FROM HealthcarePractitionerFacility
                WHERE AccountId = :accountId ORDER BY CreatedDate DESC];  
            
            for (HealthcarePractitionerFacility record : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id', record.Id != null ? record.Id : '');
                data.put('professionalName', record.Name != null ? record.Name : '');
                data.put('specialty', record.Specialty__c != null ? record.Specialty__c : '');
                data.put('phoneNumber', record.Phone__c != null ? record.Phone__c : '');
                data.put('email', record.Email__c != null ? record.Email__c : '');
                data.put('faxNumber', record.Fax_Number__c != null ? record.Fax_Number__c : '');
                data.put('website', record.Website__c != null ? record.Website__c : '');
                data.put('accountId', accountId);                
                Map<String, Object> address = new Map<String, Object>();
                if (record.Address__c != null) {
                    address.put('street', record.Address__c.getStreet() != null ? record.Address__c.getStreet() : '');
                    address.put('city', record.Address__c.getCity() != null ? record.Address__c.getCity() : '');
                    address.put('state', record.Address__c.getState() != null ? record.Address__c.getState() : '');
                    address.put('zipCode', record.Address__c.getPostalCode() != null ? record.Address__c.getPostalCode() : '');
                    address.put('country', record.Address__c.getCountry() != null ? record.Address__c.getCountry() : '');
                }
                data.put('address', address);
                professionals.add(data);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting healthcare professionals: ' + e.getMessage() + '\nStack: ' + e.getStackTraceString());
        }
        return professionals;
    }  
    
    public static List<Map<String, Object>> getInsuranceDetails(Id accountId) {
        List<Map<String, Object>> insurance = new List<Map<String, Object>>();
        try {
            List<MemberPlan> records = [
                SELECT Id, Name, medicalcoverage__Payer_Name__c, GroupNumber, MemberNumber, 
                medicalcoverage__Subscriber_First_Name__c, medicalcoverage__Subscriber_Last_Name__c, 
                medicalcoverage__Subscriber_Birth_Date__c, RelationshipToSubscriber, PrimarySecondaryTertiary, 
                OwnerId, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById
                FROM MemberPlan
                WHERE MemberId = :accountId 
                ORDER BY CreatedDate DESC
            ]; 
            
            for (MemberPlan record : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id', record.Id != null ? record.Id : '');
                data.put('Name', record.Name != null ? record.Name : '');
                data.put('providerName', record.medicalcoverage__Payer_Name__c != null ? record.medicalcoverage__Payer_Name__c : '');
                data.put('GroupNumber', record.GroupNumber != null ? record.GroupNumber : '');
                data.put('memberNumber', record.MemberNumber != null ? record.MemberNumber : '');
                data.put('Subscriber_First_Name', record.medicalcoverage__Subscriber_First_Name__c != null ? record.medicalcoverage__Subscriber_First_Name__c : '');
                data.put('Subscriber_Last_Name', record.medicalcoverage__Subscriber_Last_Name__c != null ? record.medicalcoverage__Subscriber_Last_Name__c : '');
                data.put('Subscriber_Birth_Date', record.medicalcoverage__Subscriber_Birth_Date__c != null ? formatDateTime(record.medicalcoverage__Subscriber_Birth_Date__c) : null);
                data.put('RelationshipToSubscriber', record.RelationshipToSubscriber != null ? record.RelationshipToSubscriber : '');
                data.put('PrimarySecondaryTertiary', record.PrimarySecondaryTertiary != null ? record.PrimarySecondaryTertiary : '');
                data.put('OwnerId', record.OwnerId != null ? record.OwnerId : '');
                data.put('CreatedDate', record.CreatedDate != null ? formatDateTime(record.CreatedDate) : null);
                data.put('CreatedById', record.CreatedById != null ? record.CreatedById : '');
                data.put('LastModifiedDate', record.LastModifiedDate != null ? formatDateTime(record.LastModifiedDate) : null);
                data.put('LastModifiedById', record.LastModifiedById != null ? record.LastModifiedById : '');
                data.put('accountId', accountId != null ? accountId : '');
                insurance.add(data);
            }
        } catch (Exception e) {
            System.debug('Error getting insurance details: ' + e.getMessage());
        }
        return insurance;
    }    
    
    public static List<Map<String, Object>> getDocuments(Id accountId, Id contactId) {
    List<Map<String, Object>> documents = new List<Map<String, Object>>();
    if (accountId == null) return documents;

    List<ContentDocumentLink> cdlList = [
        SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility,
               ContentDocument.Title,
               ContentDocument.FileType,
               ContentDocument.FileExtension,
               ContentDocument.ContentSize,
               ContentDocument.CreatedDate,
               ContentDocument.CreatedById,
               ContentDocument.LastModifiedDate,
               ContentDocument.LastModifiedById,
               ContentDocument.LatestPublishedVersion.Related_File__c,
               ContentDocument.OwnerId,
               ContentDocument.LatestPublishedVersionId,
               ContentDocument.LatestPublishedVersion.VersionNumber,
               ContentDocument.LatestPublishedVersion.PathOnClient
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :accountId
    ];

    if (cdlList.isEmpty()) return documents;

    Set<Id> contentDocumentIds = new Set<Id>();
    for (ContentDocumentLink cdl : cdlList) {
        contentDocumentIds.add(cdl.ContentDocumentId);
    }

    Map<Id, ContentVersion> docIdToVersionMap = new Map<Id, ContentVersion>();
    for (ContentVersion cv : [
        SELECT Id, ContentDocumentId, Service_Date_Time__c,
               Description, Organization_Name__c, CreatedDate
        FROM ContentVersion
        WHERE ContentDocumentId IN :contentDocumentIds
          AND IsLatest = true
          AND Send_File_to_Portal__c = true
        ORDER BY CreatedDate DESC
    ]) {
        if (!docIdToVersionMap.containsKey(cv.ContentDocumentId)) {
            docIdToVersionMap.put(cv.ContentDocumentId, cv);
        }
    }

    if (docIdToVersionMap.isEmpty()) return documents;

    Map<Id, String> docIdToPublicUrlMap = getOrCreatePublicLinks(docIdToVersionMap);

    Set<Id> processedDocs = new Set<Id>();

    for (ContentDocumentLink cdl : cdlList) {
        if (processedDocs.contains(cdl.ContentDocumentId)) continue;
        processedDocs.add(cdl.ContentDocumentId);

        ContentVersion cv = docIdToVersionMap.get(cdl.ContentDocumentId);
        if (cv == null) continue;

        Map<String, Object> doc = new Map<String, Object>();

        doc.put('ContentDocumentId', cdl.ContentDocumentId);
        doc.put('Id', cv.Id);
        doc.put('ShareType', cdl.ShareType);
        doc.put('Visibility', cdl.Visibility);
        doc.put('Title', cdl.ContentDocument.Title);
        doc.put('FileType', cdl.ContentDocument.FileType);
        doc.put('FileExtension', cdl.ContentDocument.FileExtension);
        doc.put('contactId', contactId != null ? String.valueOf(contactId) : '');
        doc.put('ContentSize', cdl.ContentDocument.ContentSize);
        doc.put('CreatedDate', cv.Service_Date_Time__c); 
        doc.put('CreatedById', cdl.ContentDocument.CreatedById);
        doc.put('LastModifiedDate', cdl.ContentDocument.LastModifiedDate);
        doc.put('LastModifiedById', cdl.ContentDocument.LastModifiedById);
        doc.put('OwnerId', cdl.ContentDocument.OwnerId);
        doc.put('LatestPublishedVersionId', cdl.ContentDocument.LatestPublishedVersionId);
        doc.put('relatedFile',
                cdl.ContentDocument.LatestPublishedVersion.Related_File__c);
        doc.put('PublicUrl', docIdToPublicUrlMap.get(cdl.ContentDocumentId));
        doc.put('VersionNumber',
            String.valueOf(cdl.ContentDocument.LatestPublishedVersion.VersionNumber));
        doc.put('PathOnClient',
            cdl.ContentDocument.LatestPublishedVersion.PathOnClient);
        doc.put('Description', cv.Description);
        doc.put('Organization', cv.Organization_Name__c); 

        documents.add(doc);
    }

    return documents;
}


private static void preparePublicLinks(Id accountId, Id contactId) {
    if (accountId == null) return;

    List<ContentDocumentLink> cdlList = [
        SELECT ContentDocumentId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :accountId
    ];
    if (cdlList.isEmpty()) return;

    Set<Id> contentDocumentIds = new Set<Id>();
    for (ContentDocumentLink cdl : cdlList) {
        contentDocumentIds.add(cdl.ContentDocumentId);
    }

    Map<Id, ContentVersion> docIdToVersionMap = new Map<Id, ContentVersion>();
    for (ContentVersion cv : [
        SELECT Id, ContentDocumentId
        FROM ContentVersion
        WHERE ContentDocumentId IN :contentDocumentIds
          AND IsLatest             = true
          AND Send_File_to_Portal__c = true
        ORDER BY CreatedDate DESC
    ]) {
        if (!docIdToVersionMap.containsKey(cv.ContentDocumentId)) {
            docIdToVersionMap.put(cv.ContentDocumentId, cv);
        }
    }
    if (docIdToVersionMap.isEmpty()) return;

    Set<Id> versionIds = new Set<Id>();
    for (ContentVersion cv : docIdToVersionMap.values()) {
        versionIds.add(cv.Id);
    }

    Set<Id> alreadyLinked = new Set<Id>();
    for (ContentDistribution cd : [
        SELECT ContentVersionId
        FROM ContentDistribution
        WHERE ContentVersionId IN :versionIds
    ]) {
        alreadyLinked.add(cd.ContentVersionId);
    }

  
    List<ContentDistribution> toInsert = new List<ContentDistribution>();
    for (ContentVersion cv : docIdToVersionMap.values()) {
        if (!alreadyLinked.contains(cv.Id)) {
            ContentDistribution cd = new ContentDistribution();
            cd.Name                              = 'Public Link for Portal';
            cd.ContentVersionId                  = cv.Id;
            cd.PreferencesAllowOriginalDownload  = true;
            cd.PreferencesAllowPDFDownload       = true;
            cd.PreferencesNotifyOnVisit          = false;
            cd.PreferencesPasswordRequired       = false;
            cd.PreferencesLinkLatestVersion      = true;
            toInsert.add(cd);
        }
    }

    if (!toInsert.isEmpty()) {
        insert toInsert; 
    }
}
    
    private static Map<Id, String> getOrCreatePublicLinks(
        Map<Id, ContentVersion> docIdToVersionMap) {

    Map<Id, String> resultMap = new Map<Id, String>();
    if (docIdToVersionMap.isEmpty()) return resultMap;

    Set<Id> versionIds = new Set<Id>();
    for (ContentVersion cv : docIdToVersionMap.values()) {
        versionIds.add(cv.Id);
    }

    for (ContentDistribution cd : [
        SELECT ContentDocumentId, ContentDownloadUrl
        FROM ContentDistribution
        WHERE ContentVersionId IN :versionIds
    ]) {
        resultMap.put(cd.ContentDocumentId, cd.ContentDownloadUrl);
    }

    return resultMap;
}
    private static HttpResponse sendHttpRequest(String endpoint, Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(payload));	
        System.debug('Request Body: ' + JSON.serialize(payload));
        return new Http().send(req);
    }
    
    private static String formatDateTime(Object dt) {
        if (dt instanceof Datetime)
            return ((Datetime)dt).format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        if (dt instanceof Date) {
            Date d = (Date)dt;
            return Datetime.newInstance(d.year(), d.month(), d.day())
                .format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
        return '';
    }
}