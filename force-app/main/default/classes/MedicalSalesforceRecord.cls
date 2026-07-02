public class MedicalSalesforceRecord {   
    public static void sendPatientDataToThirdParty(Set<Id> accountIds, String operation, String objectType, Set<Id> changedRecordIds) {
        if(accountIds == null || accountIds.isEmpty()) {
            System.debug('No account IDs provided');
            return;
        }        
        if(System.isFuture() || System.isBatch()) {
            System.debug('Already in async context, processing synchronously');
            processBatchSynchronously(new List<Id>(accountIds), operation, objectType, changedRecordIds);
            return;
        }        
        List<Id> accountIdList = new List<Id>(accountIds);
        Integer batchSize = 10;        
        for(Integer i = 0; i < accountIdList.size(); i += batchSize) {
            Integer endIndex = Math.min(i + batchSize, accountIdList.size());
            List<Id> batchIds = new List<Id>();
            for(Integer j = i; j < endIndex; j++) {
                batchIds.add(accountIdList[j]);
            }
            sendBatchToThirdPartyFuture(JSON.serialize(batchIds), operation, objectType, JSON.serialize(new List<Id>(changedRecordIds)));
        }
    }    
    public static void sendPatientDataToThirdParty(Id accountId, String operation, String objectType, Set<Id> changedRecordIds) {
        if(accountId == null) {
            System.debug('No account ID provided');
            return;
        }        
        if(System.isFuture() || System.isBatch()) {
            System.debug('Already in async context, processing synchronously');
            processSingleAccountSynchronously(accountId, operation, objectType, changedRecordIds);
            return;
        }        
        sendToThirdPartyFuture(accountId, operation, objectType, JSON.serialize(new List<Id>(changedRecordIds)));
    }    
    public static void processBatchSynchronously(List<Id> accountIds, String operation, String objectType, Set<Id> changedRecordIds) {
        try {
            BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
            if(apiConfig == null || String.isBlank(apiConfig.Api_Key__c)) {
                System.debug(LoggingLevel.ERROR, 'API configuration not found');
                return;
            }            
            String endpoint = apiConfig.Api_Key__c;            
            for(Id accountId : accountIds) {
                try {
                    Map<String, Object> payload = buildTargetedPayload(accountId, objectType, changedRecordIds);
                    if(payload == null || payload.isEmpty()) {
                        System.debug('No data to send for: ' + accountId);
                        continue;
                    }                    
                    payload.put('operation', operation);
                    payload.put('objectType', objectType);
                    
                    HttpResponse response = sendHttpRequest(endpoint, payload);
                    if(response != null) {
                        System.debug('Account: ' + accountId + ' - Response: ' + response.getStatusCode());
                    }
                } catch(Exception ex) {
                    System.debug(LoggingLevel.ERROR, 'Error processing: ' + accountId + ' - ' + ex.getMessage());
                }
            }
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Sync processing error: ' + ex.getMessage());
        }
    }    
    public static void processSingleAccountSynchronously(Id accountId, String operation, String objectType, Set<Id> changedRecordIds) {
        try {
            BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
            if(apiConfig == null || String.isBlank(apiConfig.Api_Key__c)) {
                System.debug(LoggingLevel.ERROR, 'API configuration not found');
                return;
            }            
            String endpoint = apiConfig.Api_Key__c;
            Map<String, Object> payload = buildTargetedPayload(accountId, objectType, changedRecordIds);            
            if(payload == null || payload.isEmpty()) {
                return;
            }            
            payload.put('operation', operation);
            payload.put('objectType', objectType);            
            HttpResponse response = sendHttpRequest(endpoint, payload);
            if(response != null) {
                System.debug('Response Code: ' + response.getStatusCode());
            }
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error: ' + ex.getMessage());
        }
    }    
    @future(callout=true)
    public static void sendBatchToThirdPartyFuture(String accountIdsJson, String operation, String objectType, String changedRecordIdsJson) {
        try {
            List<Id> accountIds = (List<Id>)JSON.deserialize(accountIdsJson, List<Id>.class);
            Set<Id> changedRecordIds = new Set<Id>((List<Id>)JSON.deserialize(changedRecordIdsJson, List<Id>.class));            
            BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
            if(apiConfig == null || String.isBlank(apiConfig.Api_Key__c)) {
                System.debug(LoggingLevel.ERROR, 'API configuration not found in Custom Setting');
                return;
            }            
            String endpoint = apiConfig.Api_Key__c;            
            for(Id accountId : accountIds) {
                Map<String, Object> payload = buildTargetedPayload(accountId, objectType, changedRecordIds);
                if(payload == null || payload.isEmpty()) {
                    System.debug('No data to send for: ' + accountId);
                    continue;
                }                
                payload.put('operation', operation);
                payload.put('objectType', objectType);                
                HttpResponse response = sendHttpRequest(endpoint, payload);
                if(response != null) {
                    System.debug('Account: ' + accountId + ' - Response Code: ' + response.getStatusCode());
                    if(response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                        System.debug('Successfully sent data for account: ' + accountId);
                    } else {
                        System.debug(LoggingLevel.ERROR, 'Failed for account: ' + accountId + ' Status: ' + response.getStatusCode() + ' Body: ' + response.getBody());
                    }
                }
            }
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Batch processing error: ' + ex.getMessage() + '\nStack: ' + ex.getStackTraceString());
        }
    }    
    @future(callout=true)
    public static void sendToThirdPartyFuture(Id accountId, String operation, String objectType, String changedRecordIdsJson) {
        try {
            Set<Id> changedRecordIds = new Set<Id>((List<Id>)JSON.deserialize(changedRecordIdsJson, List<Id>.class));            
            BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
            if(apiConfig == null || String.isBlank(apiConfig.Api_Key__c)) {
                System.debug(LoggingLevel.ERROR, 'API configuration not found in Custom Setting');
                return;
            }            
            String endpoint = apiConfig.Api_Key__c;
            Map<String, Object> payload = buildTargetedPayload(accountId, objectType, changedRecordIds);            
            if(payload == null || payload.isEmpty()) {
                return;
            }            
            payload.put('operation', operation);
            payload.put('objectType', objectType);            
            HttpResponse response = sendHttpRequest(endpoint, payload);
            if(response != null) {                
                if(response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    System.debug('Successfully sent data to third party');
                } else {
                    System.debug(LoggingLevel.ERROR, 'Failed to send data. Status: ' + response.getStatusCode());
                }
            }
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error: ' + ex.getMessage() + '\nStack Trace: ' + ex.getStackTraceString());
        }
    }
    public static Map<String, Object> buildTargetedPayload(Id accountId, String objectType, Set<Id> changedRecordIds) {
        Map<String, Object> payload = new Map<String, Object>();        
        try {
            List<Account> accounts = [SELECT Id, PersonContactId FROM Account WHERE Id = :accountId AND IsPersonAccount = true LIMIT 1];
            if(accounts.isEmpty()) {
                return payload;
            }            
            Account personAccount = accounts[0];
            payload.put('accountId', String.valueOf(personAccount.Id));            
            if(personAccount.PersonContactId != null) {
                payload.put('contactId', String.valueOf((Id)personAccount.PersonContactId));
            }
            
            if(objectType == 'Account') {
                payload.put('basic_details', getBasicDetails(accountId, changedRecordIds));
            }
            else if(objectType == 'AllergyIntolerance') {
                payload.put('allergies', getAllergies(accountId, changedRecordIds));
            } else if(objectType == 'MedicationStatement') {
                payload.put('medications', getMedications(accountId, changedRecordIds));
            } else if(objectType == 'HealthCondition') {
                payload.put('medical_history', getMedicalHistory(accountId, changedRecordIds));
            } else if(objectType == 'HealthCareProcedure') {
                payload.put('surgical_history', getSurgicalHistory(accountId, changedRecordIds));
            } else if(objectType == 'MemberPlan') {
                payload.put('insurance_details', getInsuranceDetails(accountId, changedRecordIds));
            } else if(objectType == 'Contact') {
                payload.put('personal_contacts', getPersonalContacts(accountId, changedRecordIds));
            } else if(objectType == 'HealthcareFacility') {
                payload.put('healthcare_facilities', getHealthcareFacilities(accountId, changedRecordIds));
            } else if(objectType == 'HealthcarePractitionerFacility') {
                payload.put('healthcare_professionals', getHealthcareProfessionals(accountId, changedRecordIds));
            } else if(objectType == 'CareObservation') {
                payload.put('labs', getLabs(accountId, changedRecordIds));
            }
            else if(objectType == 'PatientImmunization') {
                payload.put('immunization', getImmunizations(accountId, changedRecordIds));
            }
            else {
                System.debug(LoggingLevel.WARN, 'Unknown object type: ' + objectType);
            }
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error building payload: ' + ex.getMessage() + '\nStack: ' + ex.getStackTraceString());
        }        
        return payload;
    }
    
    
    public static List<Map<String, Object>> getBasicDetails(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> basicDetails = new List<Map<String, Object>>();
        try {
            List<Account> accounts = [
                SELECT Id, Height_in_inches__pc,PersonContactId,Weight_in_pounds__pc, Patient_Summary__c,Last_Refresh_Date__c
                FROM Account
                WHERE Id = :accountId AND IsPersonAccount = true AND Id IN :recordIds
                LIMIT 1];
            
            if (accounts.isEmpty()) return basicDetails;
            
            Account a = accounts[0];
            Map<String, Object> data = new Map<String, Object>();
            data.put('id', a.Id != null ? String.valueOf(a.Id) : null);
            data.put('accountId', a.Id != null ? String.valueOf(a.Id) : null);
            data.put('contactId', a.PersonContactId != null ? String.valueOf(a.PersonContactId) : null);
            data.put('height', a.Height_in_inches__pc != null ? String.valueOf(a.Height_in_inches__pc) : null);
            data.put('weight', a.Weight_in_pounds__pc != null ? String.valueOf(a.Weight_in_pounds__pc) : null);
            data.put('summary', a.Patient_Summary__c != null ? a.Patient_Summary__c : '');
            basicDetails.add(data);
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error getting basic details: ' + ex.getMessage());
        }
        return basicDetails;
    }
    
    @TestVisible
    private static List<Map<String, Object>> getAllergies(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> allergies = new List<Map<String, Object>>();
        try {
            List<AllergyIntolerance> records = [
                SELECT Id, Name, CreatedDate, LastModifiedDate, Generic__c, Severity,Combine_allergy_and_Generic__c, OnsetStartDateTime, 
                Allergy_Name__c, Reaction__c, Status, Type, Note__c, PatientId
                FROM AllergyIntolerance
                WHERE PatientId = :accountId AND Id IN :recordIds
                ORDER BY OnsetStartDateTime DESC NULLS LAST, CreatedDate DESC];            
            for(AllergyIntolerance alr : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id', alr.Id != null ? alr.Id : '');
                data.put('name', String.isNotBlank(alr.Combine_allergy_and_Generic__c) ? alr.Combine_allergy_and_Generic__c : (String.isNotBlank(alr.Allergy_Name__c) ? alr.Allergy_Name__c : ''));
                data.put('severity', alr.Severity != null ? alr.Severity : '');
                data.put('reaction', alr.Reaction__c);
                data.put('note', alr.Note__c != null ? alr.Note__c : '');
                data.put('status', alr.Status != null ? alr.Status : '');
                data.put('generic', alr.Generic__c != null ? alr.Generic__c : '');
                data.put('patientId', alr.PatientId != null ? alr.PatientId : '');
                allergies.add(data);
            }
        } catch(Exception ex) {
            System.debug('Error getting allergies: ' + ex.getMessage());
        }
        return allergies;
    }      
    
    @TestVisible
    private static List<Map<String, Object>> getMedications(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> medications = new List<Map<String, Object>>();
        try {
            List<MedicationStatement> records = [
                SELECT Id, Name, MedicationId, Dose__c, PatientId, Frequency__c, Reason__c, 
                StartDateTime, EndDateTime, Status, Comments__c, Medication.Name, CreatedDate, LastModifiedDate
                FROM MedicationStatement
                WHERE PatientId = :accountId AND Id IN :recordIds
                ORDER BY CreatedDate DESC
            ];
            
            for(MedicationStatement md : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id', md.Id != null ? md.Id : '');
                data.put('medicationId', md.MedicationId != null ? md.MedicationId : '');
                data.put('medication', md.Medication != null && md.Medication.Name != null ? md.Medication.Name : '');
                data.put('dosage', md.Dose__c != null ? md.Dose__c : '');
                data.put('frequency', md.Frequency__c != null ? md.Frequency__c : '');
                data.put('reason', md.Reason__c != null ? md.Reason__c : '');
                data.put('startDate', md.StartDateTime != null ? formatDateTime(md.StartDateTime) : null);
                data.put('endDate', md.EndDateTime != null ? formatDateTime(md.EndDateTime) : null);
                data.put('status', md.Status != null ? md.Status : '');
                data.put('notes', md.Comments__c != null ? md.Comments__c : '');
                data.put('patientId', md.PatientId != null ? md.PatientId : '');
                medications.add(data);
            }
        } catch (Exception ex) {
            System.debug('Error getting medications: ' + ex.getMessage());
        }
        return medications;
    }
    
    @TestVisible
    private static List<Map<String, Object>> getMedicalHistory(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> history = new List<Map<String, Object>>();
        try {
            List<HealthCondition> records = [
                SELECT Id, Name, CreatedDate, LastModifiedDate, OnsetStartDateTime, OnsetEndDateTime, 
                ConditionStatus, Type, Severity, ProblemName, ProblemDescription, PatientId
                FROM HealthCondition
                WHERE PatientId = :accountId AND Id IN :recordIds
                ORDER BY OnsetStartDateTime DESC NULLS LAST, CreatedDate DESC];         
            for (HealthCondition medi : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id', medi.Id != null ? medi.Id : '');
                data.put('name', String.isNotBlank(medi.ProblemName) ? medi.ProblemName : '');
                data.put('medicalProblem', String.isNotBlank(medi.ProblemName) ? medi.ProblemName : '');
                data.put('note', medi.ProblemDescription != null ? medi.ProblemDescription : '');
                data.put('onsetDate', medi.OnsetStartDateTime != null ? formatDateTime(medi.OnsetStartDateTime) : null);
                data.put('status', medi.ConditionStatus != null ? medi.ConditionStatus : '');
                data.put('severity', medi.Severity != null ? medi.Severity : '');
                data.put('patientId', medi.PatientId != null ? medi.PatientId : '');
                history.add(data);
            }
        } catch (Exception ex) {
            System.debug('Error getting medical history: ' + ex.getMessage());
        }
        return history;
    }    
    @TestVisible
    private static List<Map<String, Object>> getSurgicalHistory(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> surgeries = new List<Map<String, Object>>();
        try {
            List<HealthCareProcedure> records = [
                SELECT Id, Name, CreatedDate, LastModifiedDate, CodeShortDescription, CodeDescription, 
                EffectiveDate, EndDate, Surgery_Name__c, Patient__c
                FROM HealthCareProcedure
                WHERE Patient__c = :accountId AND Id IN :recordIds
                ORDER BY EffectiveDate DESC NULLS LAST, CreatedDate DESC
            ];            
            for (HealthCareProcedure record : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id', record.Id != null ? record.Id : '');
                data.put('name', String.isNotBlank(record.Surgery_Name__c) ? record.Surgery_Name__c : (String.isNotBlank(record.Name)
                                                                                                       ? record.Name : ''));
                data.put('surgeryDate', record.EffectiveDate != null ? formatDateTime(record.EffectiveDate) : null);
                data.put('note', record.CodeDescription != null ? record.CodeDescription : '');
                data.put('patientId', record.Patient__c != null ? record.Patient__c : '');
                surgeries.add(data);
            }
        } catch (Exception e) {
            System.debug('Error getting surgical history: ' + e.getMessage());
        }
        return surgeries;
    }    
    @TestVisible
    private static List<Map<String, Object>> getInsuranceDetails(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> insurance = new List<Map<String, Object>>();
        try {
            List<MemberPlan> records = [
                SELECT Id, Name, medicalcoverage__Payer_Name__c, GroupNumber, MemberNumber, 
                medicalcoverage__Subscriber_First_Name__c, medicalcoverage__Subscriber_Last_Name__c, 
                medicalcoverage__Subscriber_Birth_Date__c, RelationshipToSubscriber, PrimarySecondaryTertiary, 
                OwnerId, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById
                FROM MemberPlan
                WHERE MemberId = :accountId AND Id IN :recordIds
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
    @TestVisible
    private static List<Map<String, Object>> getPersonalContacts(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> contacts = new List<Map<String, Object>>();
        try {
            List<Contact> records = [
                SELECT Id, FirstName, AccountId, LastName, Email, MobilePhone, HomePhone, 
                Emergency_Contact_Relationship__c, MailingStreet, MailingCity, Account__c, 
                MailingState, MailingPostalCode, MailingCountry, Description, Emergency_Contact__c, ADT_Contact__c,Authorized_Representative__c,
                Is_PHI_Authorized__c, Is_Healthcare_Proxy__c, CreatedDate, LastModifiedDate
                FROM Contact
                WHERE Account__c = :accountId AND Id IN :recordIds
                ORDER BY CreatedDate DESC
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
    @TestVisible
    private static List<Map<String, Object>> getHealthcareFacilities(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> facilities = new List<Map<String, Object>>();
        try {
            List<HealthcareFacility> records = [
                SELECT Id, Name, AccountId, Phone__c, Email__c, Facility_type__c, Fax_Number__c, 
                Website__c, Mailing_Address__c, CreatedDate, LastModifiedDate
                FROM HealthcareFacility
                WHERE AccountId = :accountId AND Id IN :recordIds
                ORDER BY CreatedDate DESC
            ];            
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
    @TestVisible
    private static List<Map<String, Object>> getHealthcareProfessionals(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> professionals = new List<Map<String, Object>>();
        try {
            List<HealthcarePractitionerFacility> records = [
                SELECT Id, Name, AccountId, PractitionerId, Fax_Number__c, Website__c, 
                Practitioner.Name, Phone__c, Email__c, Specialty__c, EffectiveFrom, 
                EffectiveTo, Address__c, CreatedDate, LastModifiedDate
                FROM HealthcarePractitionerFacility
                WHERE AccountId = :accountId AND Id IN :recordIds
                ORDER BY CreatedDate DESC];            
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
    
    @TestVisible
    private static List<Map<String, Object>> getLabs(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> labs = new List<Map<String, Object>>();
        if (accountId == null) return labs;
        try {
            List<CareObservation> records = [
                SELECT Id, Name, ObservedSubjectId, Category, ObservationStatus,
                Range_High__c,Range_Low__c, Value_Quantity__c,ValueInterpretation,EffectiveDateTime,Effective_Date_and_Time_Display__c
                FROM CareObservation
                WHERE ObservedSubjectId = :accountId
                AND Id IN :recordIds
                ORDER BY CreatedDate DESC
            ];
            
            for (CareObservation record : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id',                record.Id);
                data.put('Name',         record.Name != null ? record.Name : '');
                data.put('accountId',         record.ObservedSubjectId);
                data.put('Category',          record.Category);
                data.put('ObservationStatus', record.ObservationStatus);
                data.put('Range_High',        record.Range_High__c);
                data.put('Range_Low',         record.Range_Low__c);
                data.put('Value_Quantity', String.isBlank(String.valueOf(record.Value_Quantity__c)) ? record.Observed_Value__c : record.Value_Quantity__c);
                data.put('Value_Interpretation',  record.ValueInterpretation);
                data.put('Effective_Date',  record.Effective_Date_and_Time_Display__c);
                labs.add(data);
            }
            
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error in getLabs: ' + ex.getMessage() + '\nStack: ' + ex.getStackTraceString());
        }
        return labs;
    }  
    
     public static List<Map<String, Object>> getImmunizations(Id accountId, Set<Id> recordIds) {
        List<Map<String, Object>> Immunizations = new List<Map<String, Object>>();
        if (accountId == null) return Immunizations;
        try{
            List<PatientImmunization> records = [
                SELECT Id, Vaccine_Name__c,Status,VaccinationDate, PatientId FROM 
                PatientImmunization WHERE PatientId = :accountId AND Id IN :recordIds ORDER BY CreatedDate DESC
                ];
            
            for (PatientImmunization record : records) {
                Map<String, Object> data = new Map<String, Object>();
                data.put('id',                record.Id);
                data.put('name', record.Vaccine_Name__c != null ? record.Vaccine_Name__c : '');
                data.put('accountId',         record.PatientId);
                data.put('status',          record.Status);
                data.put('vaccine_date', record.VaccinationDate);
             
                Immunizations.add(data);
            }  
        } catch (Exception  ex) {
            System.debug(LoggingLevel.ERROR, 'Error in Immunizations : ' + ex.getMessage() + '\nStack: ' + ex.getStackTraceString());
            
        }
        return Immunizations;
    }
    
    @TestVisible
    private Static HttpResponse sendHttpRequest(String endpoint, Map<String, Object> payload){
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);        
        String jsonPayload = JSON.serialize(payload);
        req.setBody(jsonPayload);
        System.debug('Payload:\n' + JSON.serializePretty(payload));        
        Http http = new Http();
        HttpResponse res = http.send(req);
        return res;
    }   
    
    @TestVisible
    private static String formatDateTime(Object dt) {
        if (dt == null) return null;        
        if (dt instanceof Datetime) {
            return ((Datetime)dt).format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        } else if (dt instanceof Date) {
            Datetime convertedDt = Datetime.newInstance(((Date)dt).year(), ((Date)dt).month(), ((Date)dt).day());
            return convertedDt.format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
        return null;
    }
}