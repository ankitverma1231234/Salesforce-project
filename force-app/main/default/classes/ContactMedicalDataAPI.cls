@RestResource(urlMapping='/ContactMedicalData/v1/*')
global without sharing class ContactMedicalDataAPI {
   
    @HttpPost
    global static ContactMedicalDataWrappers.ResponseWrapper getContactData() {
        RestRequest req = RestContext.request;
        req.addHeader('Access-Control-Allow-Origin', '*');
        req.addHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
        req.addHeader('Content-Type', 'application/json');
        
        String requestBody = req.requestBody.toString();
        
        Map<String, Object> bodyData = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
        
        String email      = (String) bodyData.get('email');
        String phone      = (String) bodyData.get('phone');
        String firstName  = (String) bodyData.get('firstName');
        String lastName   = (String) bodyData.get('lastName');
        
        if (String.isBlank(email) || String.isBlank(phone)) {
            ContactMedicalDataWrappers.ResponseWrapper res = new ContactMedicalDataWrappers.ResponseWrapper();
            res.success = false;
            res.message = 'Email and Phone are required for search';
            return res;
        }
        
        ContactMedicalDataWrappers.ResponseWrapper searchResult = searchContactData(email, phone, firstName, lastName);
        return searchResult;
    }
    
    /* ============================================================================
CORE CONTACT SEARCH
============================================================================ */
    private static ContactMedicalDataWrappers.ResponseWrapper searchContactData(String email, String phone, String firstName, String lastName) {
        ContactMedicalDataWrappers.ResponseWrapper res = new ContactMedicalDataWrappers.ResponseWrapper();
        
        res.searchedEmail = email;
        res.searchedPhone = phone;
        res.searchedFirstName = firstName;
        res.searchedLastName = lastName;
        
        String phoneTrimmed = String.isBlank(phone) ? null : phone.trim();
        String cleanPhone = (phoneTrimmed == null) ? null : cleanPhoneNumber(phoneTrimmed);
        res.debugInfo = new ContactMedicalDataWrappers.DebugInfo();
        res.debugInfo.originalPhone = phone;
        res.debugInfo.trimmedPhone = phoneTrimmed;
        res.debugInfo.cleanedPhone = cleanPhone;
        
        if (String.isBlank(email) || String.isBlank(phone)) {
            res.success = false;
            res.message = 'Email and phone are required for search';
            res.errorCode = 'MISSING_REQUIRED_FIELDS';
            return res;
        }
        
        try {
            List<Contact> conList = findContact(email, phone, firstName, lastName);
            if(conList.isEmpty()) {
                res.success = false;
                res.message = 'Contact not found';
                res.errorCode = 'CONTACT_NOT_FOUND';
                return res;
            }
            Map<Id, ContactMedicalDataWrappers.ContactData> mapData = buildContactDataBulk(conList);
            Contact c = conList[0];
            ContactMedicalDataWrappers.ContactData cd = mapData.get(c.Id);
            
            // Surgery
            List<ContactMedicalDataWrappers.SurgeryData> surgeries = getSurgeryRecords(c.AccountId);
            cd.surgeries = (surgeries != null) ? surgeries : new List<ContactMedicalDataWrappers.SurgeryData>();
            
            // Medical history
            List<ContactMedicalDataWrappers.MedicalHistoryData> medHistory = getMedicalHistoryRecords(c.AccountId);
            cd.medicalHistory = (medHistory != null) ? medHistory : new List<ContactMedicalDataWrappers.MedicalHistoryData>();
            
            // Allergies
            List<ContactMedicalDataWrappers.AllergyData> allergies = getAllergyRecords(c.AccountId);
            cd.allergies = (allergies != null) ? allergies : new List<ContactMedicalDataWrappers.AllergyData>();
            
            // Medications Statement
            List<ContactMedicalDataWrappers.MedicationData> medications = getMedicationStatementRecords(c.AccountId);
            cd.medications = (medications != null) ? medications : new List<ContactMedicalDataWrappers.MedicationData>();
            // Medications
            List<ContactMedicalDataWrappers.Medication> medicationRecords = getMedicationRecords();
            cd.medicationsList = (medicationRecords  != null) ? medicationRecords : new List<ContactMedicalDataWrappers.Medication>();
            // insurnce Plan
            List<ContactMedicalDataWrappers.InsuranceData> insurancePlans = getInsurancePlans(c.AccountId);
            cd.insurancePlans = (insurancePlans != null) ? insurancePlans : new List<ContactMedicalDataWrappers.InsuranceData>();
            // Healthcare Facilities
            List<ContactMedicalDataWrappers.HealthcareFacility> facilities = getHealthcareFacilities(c.AccountId);
            cd.healthcareFacilities = (facilities != null) ? facilities : new List<ContactMedicalDataWrappers.HealthcareFacility>();
            // HealthcareProfessionals
            List<ContactMedicalDataWrappers.HealthcareProfessionals> professionals = getHealthcareProfessionals(c.AccountId);
            cd.healthcareProfessionals = (professionals != null) ? professionals : new List<ContactMedicalDataWrappers.HealthcareProfessionals>();
            // personal Contacts
            List<ContactMedicalDataWrappers.PersonalContacts>contacts = getPersonalContactsOnly(c.AccountId);
            cd.personalContacts = (contacts != null) ? contacts : new List<ContactMedicalDataWrappers.PersonalContacts>();
            // Cases 
            List<ContactMedicalDataWrappers.CaseData> cases = getCaseRecords(c.AccountId);
            cd.CasemessageList = (cases != null) ? cases : new List<ContactMedicalDataWrappers.CaseData>();
            //Documents
            List<ContactMedicalDataWrappers.DocumentData> documents = getRelatedDocuments(c.AccountId);
            cd.documents = (documents != null) ? documents : new List<ContactMedicalDataWrappers.DocumentData>();
            
            res.success = true;
            res.message = 'Contact retrieved';
            res.data = cd;
            
            res.recordCount = new ContactMedicalDataWrappers.RecordCount();
            res.recordCount.surgeries = cd.surgeries.size();
            res.recordCount.medicalHistory = cd.medicalHistory.size();
            res.recordCount.allergies = cd.allergies.size();
            res.recordCount.medications = cd.medications.size();
            res.recordCount.insurancePlans = cd.insurancePlans.size();
            res.recordCount.healthcareFacilitiesCount = cd.healthcareFacilities.size();
            res.recordCount.HealthcareProfessionalCount = cd.healthcareProfessionals.size();
            res.recordCount.personalContactsCount = cd.personalContacts.size();
            res.recordCount.messageCaseCount = cd.CasemessageList.size();
            res.recordCount.documentsCount = cd.documents.size();
            
        } catch (Exception e) {
            res.success = false;
            res.message = 'Internal error';
            res.errorCode = 'INTERNAL_ERROR';
            res.errorDetails = e.getMessage();
            res.errorStackTrace = e.getStackTraceString();
        }
        
        return res;
    }
    /* ============================================================================
GET PERSON ACCOUNT RECORD TYPE ID
============================================================================ */
    public static Id getPersonAccountRecordTypeId() {
        try {
            List<RecordType> rtList = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Account' 
                AND IsPersonType = true
                AND IsActive = true
                LIMIT 1
            ];
            
            if (!rtList.isEmpty()) {
                return rtList[0].Id;
            }
        } catch (Exception e) {
            System.debug('Error getting Person Account Record Type: ' + e.getMessage());
        }
        return null;
    }
    
@TestVisible
public static List<ContactMedicalDataWrappers.DocumentData> getRelatedDocuments(Id accountId) {

    List<ContactMedicalDataWrappers.DocumentData> resultList = new List<ContactMedicalDataWrappers.DocumentData>();
    if (accountId == null) return resultList;
    List<ContentDocumentLink> cdlList = [
        SELECT Id, ContentDocumentId, LinkedEntityId,
               ContentDocument.Title,
               ContentDocument.FileType,
               ContentDocument.FileExtension,
               ContentDocument.ContentSize,
               ContentDocument.CreatedById,
               ContentDocument.LastModifiedDate,
               ContentDocument.LastModifiedById,
               ContentDocument.OwnerId,
               ContentDocument.LatestPublishedVersionId,
               ShareType, Visibility
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :accountId];

    if (cdlList.isEmpty()) return resultList;

    Set<Id> contentDocumentIds = new Set<Id>();
    for (ContentDocumentLink cdl : cdlList) {
        contentDocumentIds.add(cdl.ContentDocumentId);
    }

    Map<Id, ContentVersion> docIdToVersionMap = new Map<Id, ContentVersion>();
    for (ContentVersion cv : [
        SELECT Id, ContentDocumentId, Send_File_to_Portal__c,
        Date__c, Source__c, Description, Organization_Name__c
        FROM ContentVersion
        WHERE ContentDocumentId IN :contentDocumentIds
        AND IsLatest = true
        AND Send_File_to_Portal__c = true
    ]) {
        docIdToVersionMap.put(cv.ContentDocumentId, cv);
    }

    Map<Id, String> docIdToPublicUrlMap = createPublicLinks(docIdToVersionMap);

    for (ContentDocumentLink cdl : cdlList) {
        ContentVersion cvs = docIdToVersionMap.get(cdl.ContentDocumentId);
        if (cvs == null) continue;

        ContactMedicalDataWrappers.DocumentData doc =
            new ContactMedicalDataWrappers.DocumentData();

        doc.Id = cdl.Id;
        doc.ContentDocumentId = cdl.ContentDocumentId;
        doc.LinkedEntityId = cdl.LinkedEntityId;

        if (cdl.ContentDocument != null) {
            doc.Title = cdl.ContentDocument.Title;
            doc.FileType = cdl.ContentDocument.FileType;
            doc.FileExtension = cdl.ContentDocument.FileExtension;
            doc.ContentSize = cdl.ContentDocument.ContentSize;
            doc.CreatedById = cdl.ContentDocument.CreatedById;
            doc.LastModifiedDate = cdl.ContentDocument.LastModifiedDate;
            doc.LastModifiedById = cdl.ContentDocument.LastModifiedById;
            doc.OwnerId = cdl.ContentDocument.OwnerId;
            doc.LatestPublishedVersionId = cdl.ContentDocument.LatestPublishedVersionId;
            doc.PublicUrl = docIdToPublicUrlMap.get(cdl.ContentDocumentId);
        }

        ContentVersion cv = docIdToVersionMap.get(cdl.ContentDocumentId);
        if (cv != null) {
            doc.CreatedDate = cv.Date__c;
            doc.Description = cv.Description;
            doc.Organization_Name = cv.Organization_Name__c;
        }

        resultList.add(doc);
    }

    return resultList;
}

@TestVisible
public static Map<Id, String> createPublicLinks(
    Map<Id, ContentVersion> docIdToVersionMap) {
 
    Map<Id, String> resultMap = new Map<Id, String>();
    if (docIdToVersionMap.isEmpty()) return resultMap;
 
    Set<Id> versionIds = new Set<Id>();
    for (ContentVersion cv : docIdToVersionMap.values()) {
        versionIds.add(cv.Id);
    }
 
    Map<Id, String> existingMap = new Map<Id, String>();
    for (ContentDistribution cd : [
        SELECT ContentDocumentId, ContentDownloadUrl, ContentVersionId
        FROM ContentDistribution
        WHERE ContentVersionId IN :versionIds
    ]) {
        existingMap.put(cd.ContentDocumentId, cd.ContentDownloadUrl);
    }
 
    List<ContentDistribution> toInsert = new List<ContentDistribution>();
    for (ContentVersion cv : docIdToVersionMap.values()) {
        if (existingMap.containsKey(cv.ContentDocumentId)) {
            resultMap.put(cv.ContentDocumentId, existingMap.get(cv.ContentDocumentId));
        } else {
            ContentDistribution cd = new ContentDistribution();
            cd.Name                             = 'Public Link for Portal';
            cd.ContentVersionId                 = cv.Id;
            cd.PreferencesAllowOriginalDownload = true;
            cd.PreferencesAllowPDFDownload      = true;
            cd.PreferencesNotifyOnVisit         = false;
            cd.PreferencesPasswordRequired      = false;
            cd.PreferencesLinkLatestVersion     = true;
            toInsert.add(cd);
        }
    }
 
    if (!toInsert.isEmpty() && !Test.isRunningTest()) {  
        try {
            insert toInsert;
 
            for (ContentDistribution cd : [
                SELECT ContentDocumentId, ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id IN :toInsert
            ]) {
                resultMap.put(cd.ContentDocumentId, cd.ContentDownloadUrl);
            }
        } catch (Exception e) {
            System.debug('createPublicLinks insert error: ' + e.getMessage());
        }
    }
 
    return resultMap;
}
 

 /* ============================================================================
FIND CONTACT - UPDATED WITH PERSON ACCOUNT FIELDS
============================================================================ */
    private static List<Contact> findContact(String email, String phone, String firstName, String lastName) {
        String emailTrimmed = String.isBlank(email) ? null : email.trim();
        String phoneTrimmed = String.isBlank(phone) ? null : phone.trim();
        String cleanPhone = (phoneTrimmed == null) ? null : cleanPhoneNumber(phoneTrimmed);
        
        String query = 'SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, HomePhone, ' +
            'AccountId, Account.Name, Account__c, Account.IsPersonAccount, Account.Patient_Summary__c, ' +
            'Account.PersonEmail, Account.PersonHomePhone, Account.PersonMobilePhone, ' +
            'Account.Date_of_Birth__pc, Account.Sign_up_date__pc, Account.Maiden_Name__pc, Account.Work_Phone__pc, Account.Preferred_Language__pc, ' +
            'Account.Height_in_inches__pc, Account.Weight_in_pounds__pc,Account.sra__OptOut__c, Account.Consent_to_Call__pc, ' +
            'Account.Consent_to_Text__pc, Account.Renewal_Date__pc, Account.Preferred_Method_of_Contact__pc, ' +
            'Account.PersonMailingStreet, Account.PersonMailingCity, Account.PersonMailingState, ' +
            'Account.PersonMailingStateCode, Account.PersonMailingPostalCode, Account.PersonMailingCountry, ' +
            'Account.PersonOtherStreet, Account.PersonOtherCity, Account.PersonOtherState, ' +
            'Account.PersonOtherStateCode, Account.PersonOtherPostalCode, Account.PersonOtherCountry, ' +
            'MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry, ' +
            'Birthdate, CreatedDate, LastModifiedDate, ' +
            'Account.Preferred_Name__pc, Account.Salutation, Account.Suffix, Account.Fax, ' +
            'Account.Additional_Email__pc, Account.Occupation__pc, Account.Marital_Status__pc, ' +
            'Account.Biological_Sex_at_Birth__c, Account.Sexual_Orientation__pc, Account.Race__pc, ' +
            'Account.Ethnicity__pc,Account.PersonGenderIdentity, Account.Living_Situation__pc ' +
            'FROM Contact WHERE Account.IsPersonAccount = true';
        
        List<String> conditions = new List<String>();
        
        if (emailTrimmed != null) {
            conditions.add('(Email = \'' + String.escapeSingleQuotes(emailTrimmed) + '\' ' +
                           'OR Account.PersonEmail = \'' + String.escapeSingleQuotes(emailTrimmed) + '\')');
        }
        
        if (cleanPhone != null) {
            String phoneLike = '%' + String.escapeSingleQuotes(cleanPhone) + '%';
            conditions.add('(Phone LIKE \'' + phoneLike + '\' ' +
                           'OR MobilePhone LIKE \'' + phoneLike + '\' ' +
                           'OR HomePhone LIKE \'' + phoneLike + '\' ' +
                           'OR Account.PersonMobilePhone LIKE \'' + phoneLike + '\' ' +
                           'OR Account.PersonHomePhone LIKE \'' + phoneLike + '\')');
        }
        
        if (!conditions.isEmpty()) {
            query += ' AND (' + String.join(conditions, ' OR ') + ')';
        }
        
        query += ' ORDER BY LastModifiedDate DESC LIMIT 1';
        
        try {
            return Database.query(query);
        } catch (QueryException ex) {
            System.debug('Query Error: ' + ex.getMessage());
            return new List<Contact>(); 
        }
    }
    /* ============================================================================
BULK CONTACT DATA BUILDER
============================================================================ */
    private static Map<Id, ContactMedicalDataWrappers.ContactData> buildContactDataBulk(List<Contact> contacts) {
        Map<Id, ContactMedicalDataWrappers.ContactData> resultMap = new Map<Id, ContactMedicalDataWrappers.ContactData>();
        if (contacts == null || contacts.isEmpty()) return resultMap;
        
        for (Contact con : contacts) {
            ContactMedicalDataWrappers.ContactData d = new ContactMedicalDataWrappers.ContactData();
            
            d.contactId = con.Id;
            d.personAccountId = con.AccountId;
            d.isPersonAccount = (con.Account != null && con.Account.IsPersonAccount);
            
            d.firstName = con.FirstName;
            d.lastName = con.LastName; 
            d.fullName = (con.FirstName + ' ' + con.LastName).trim();
            d.preferredName = con.Account.Preferred_Name__pc;
            d.salutation = con.Account.Salutation;
            d.suffix = con.Account.Suffix;
            d.maidenname = con.Account.Maiden_Name__pc;
            d.genderIdentity = con.Account.PersonGenderIdentity;
            d.preferredLanguage = con.Account.Preferred_Language__pc;
            d.accountFax = con.Account.Fax;
            d.additionalEmail = con.Account.Additional_Email__pc;
            d.occupation = con.Account.Occupation__pc;
            d.maritalStatus = con.Account.Marital_Status__pc;
            d.biologicalSexAtBirth = con.Account.Biological_Sex_at_Birth__c;
            d.preferredContactMethod = con.Account.Preferred_Method_of_Contact__pc;
            d.sexualOrientation = con.Account.Sexual_Orientation__pc;
            d.race = con.Account.Race__pc;
            d.ethnicity = con.Account.Ethnicity__pc;
            d.livingSituation = con.Account.Living_Situation__pc;
            d.email = con.Email;
            d.phone = con.Account.PersonHomePhone;
            d.Date_of_Birth = (con.Account != null) ? con.Account.Date_of_Birth__pc : null;
            d.mobilePhone = con.Account.PersonHomePhone;
            d.birthdate = con.Birthdate;
            d.accountId = con.AccountId;
            d.accountName = (con.Account != null) ? con.Account.Name : null;
            d.createdDate = con.CreatedDate;
            d.lastModifiedDate = con.LastModifiedDate;
            d.Summary =(con.Account != null) ? con.Account.Patient_Summary__c : null;
            d.Sign_up_date = (con.Account != null) ? con.Account.Sign_up_date__pc : null;
            d.Work_Phone = (con.Account != null) ? con.Account.Work_Phone__pc : null;
            d.Height_in_inches = (con.Account != null) ? con.Account.Height_in_inches__pc : null;
            d.Weight_in_pounds = (con.Account != null) ? con.Account.Weight_in_pounds__pc : null;
            d.Consent_to_Call = (con.Account != null) ? con.Account.Consent_to_Call__pc : null;
            d.communicationConsent = (con.Account != null) ? con.Account.Consent_to_Text__pc : null;
            d.Renewal_date = (con.Account != null) ? con.Account.Renewal_date__pc : null;
            
            d.address = new ContactMedicalDataWrappers.AddressData();
            if (con.Account != null) {
                d.address.street = con.Account.PersonMailingStreet;
                d.address.city = con.Account.PersonMailingCity;
                d.address.state = con.Account.PersonMailingState;
                d.address.postalCode = con.Account.PersonMailingPostalCode;
                d.address.country = con.Account.PersonMailingCountry;
            }
            
            d.otheraddress = new ContactMedicalDataWrappers.OtherAddressData();
            if (con.Account != null) {
                d.otheraddress.street = con.Account.PersonOtherStreet;
                d.otheraddress.city = con.Account.PersonOtherCity;
                d.otheraddress.state = con.Account.PersonOtherState;
                d.otheraddress.postalCode = con.Account.PersonOtherPostalCode;
                d.otheraddress.country = con.Account.PersonOtherCountry;
            }
            
            d.surgeries = new List<ContactMedicalDataWrappers.SurgeryData>();
            d.medicalHistory = new List<ContactMedicalDataWrappers.MedicalHistoryData>();
            d.allergies = new List<ContactMedicalDataWrappers.AllergyData>();
            d.medications = new List<ContactMedicalDataWrappers.MedicationData>();
            d.insurancePlans = new List<ContactMedicalDataWrappers.InsuranceData>();
            d.CasemessageList = new List<ContactMedicalDataWrappers.CaseData>();
            d.documents = new List<ContactMedicalDataWrappers.DocumentData>();
            
            resultMap.put(con.Id, d);
        }
        
        return resultMap;
    }
    
    /* ============================================================================
GET PERSON ACCOUNT RELATED CASES
============================================================================ */
    private static List<ContactMedicalDataWrappers.CaseData> getCaseRecords(Id patientId) {
        List<ContactMedicalDataWrappers.CaseData> caseList = new List<ContactMedicalDataWrappers.CaseData>();
        if (patientId == null) {
            return caseList;
        }
        
        try {
            List<Case> cases = [
                SELECT Id, CaseNumber, OwnerId,Case_Type__c, Subject, Status, 
                Priority, Type, Reason, Origin, Description, 
                IsClosed, ClosedDate, CreatedDate, CreatedById,
                LastModifiedDate, LastModifiedById,
                AccountId, Account.Name, ContactId, Contact.Name,
                ParentId, SuppliedEmail, SuppliedPhone
                FROM Case WHERE AccountId = :patientId AND Case_Type__c = 'Portal Messages'
                ORDER BY CreatedDate DESC LIMIT 10000];
            
            for (Case c : cases) {
                ContactMedicalDataWrappers.CaseData caseData = new ContactMedicalDataWrappers.CaseData();
                caseData.Id = c.Id;
                caseData.CaseNumber = c.CaseNumber;
                caseData.OwnerId = c.OwnerId;
                caseData.Subject = c.Subject;
                caseData.Status = c.Status;
                caseData.Priority = c.Priority;
                caseData.Type = c.Type;
                caseData.Reason = c.Reason;
                caseData.Origin = c.Origin;
                caseData.Description = c.Description;
                caseData.ClosedDate = c.ClosedDate;
                caseData.CreatedDate = c.CreatedDate;
                caseData.CreatedById = c.CreatedById;
                caseData.LastModifiedDate = c.LastModifiedDate;
                caseData.LastModifiedById = c.LastModifiedById;
                if(c.AccountId != null){
                    caseData.AccountId = c.AccountId;
                }
                if(c.ContactId != null){
                    caseData.ContactId = c.ContactId;  
                }
                caseData.ParentId = c.ParentId;
                caseData.SuppliedEmail = c.SuppliedEmail;
                caseData.SuppliedPhone = c.SuppliedPhone;
                
                caseList.add(caseData);
            }
            
        } catch (Exception e) {
            System.debug('Error retrieving cases: ' + e.getMessage());
        }
        
        return caseList;
    }
    /* ============================================================================
SURGERY RECORDS - Using HealthCareProcedure Object
============================================================================ */
    private static List<ContactMedicalDataWrappers.SurgeryData> getSurgeryRecords(Id accountId) {
        List<ContactMedicalDataWrappers.SurgeryData> resultList = new List<ContactMedicalDataWrappers.SurgeryData>();
        if (accountId == null) {
            return resultList;
        }
        
        List<HealthCareProcedure> surgicalHistories = [
            SELECT Id, Name, CreatedDate,Patient__c, LastModifiedDate,
            CodeShortDescription, CodeDescription,Status__c,
            EffectiveDate
            FROM HealthCareProcedure
            WHERE Patient__c = :accountId
            ORDER BY EffectiveDate DESC NULLS LAST LIMIT 10000];
        
        for (HealthCareProcedure s : surgicalHistories) {
            ContactMedicalDataWrappers.SurgeryData d = new ContactMedicalDataWrappers.SurgeryData();
            
            d.Id = s.Id;
            d.name = s.CodeShortDescription != null ? s.CodeShortDescription : s.Name;
            d.Surgery_Date = s.EffectiveDate != null ? s.EffectiveDate : null;
            d.Note = s.CodeDescription;
            d.createdDate = s.CreatedDate;
            d.status = s.Status__c;
            d.lastModifiedDate = s.LastModifiedDate;
            if(s.Patient__c != null){
                d.patient = s.Patient__c;  
            }  
            resultList.add(d);
        }
        
        return resultList;
    }
    
    /* ============================================================================
MEDICAL HISTORY - Using HealthCondition Object
============================================================================ */
    private static List<ContactMedicalDataWrappers.MedicalHistoryData> getMedicalHistoryRecords(Id accountId) {
        List<ContactMedicalDataWrappers.MedicalHistoryData> resultList = new List<ContactMedicalDataWrappers.MedicalHistoryData>();
        if (accountId == null) {
            return resultList;
        }
        
        List<HealthCondition> medicalHistories = [
            SELECT Id, Name, CreatedDate, LastModifiedDate,
            OnsetStartDateTime, OnsetEndDateTime,
            ConditionStatus,Severity,
            ProblemName, ProblemDescription,
            PatientId
            FROM HealthCondition
            WHERE PatientId = :accountId
            ORDER BY OnsetStartDateTime DESC NULLS LAST LIMIT 10000];
        
        for (HealthCondition m : medicalHistories) {
            ContactMedicalDataWrappers.MedicalHistoryData d = new ContactMedicalDataWrappers.MedicalHistoryData();
            d.Id = m.Id;
            d.name = m.ProblemName != null ? m.ProblemName : m.Name;
            d.Medical_Problem = m.ProblemName != null ? m.ProblemName : m.Name;
            d.Note = m.ProblemDescription;
            d.Onset_Date = m.OnsetStartDateTime != null ? m.OnsetStartDateTime.date() : null;
            d.createdDate = m.CreatedDate;
            d.status = m.ConditionStatus;
            d.lastModifiedDate = m.LastModifiedDate;
            if (m.PatientId != null) {
                d.Patient = m.PatientId; 
            }
            resultList.add(d);
        }
        return resultList;
    }
    
    /* ============================================================================
ALLERGY RECORDS - Using AllergyIntolerance Object
============================================================================ */
    private static List<ContactMedicalDataWrappers.AllergyData> getAllergyRecords(Id accountId) {
        List<ContactMedicalDataWrappers.AllergyData> resultList = new List<ContactMedicalDataWrappers.AllergyData>();
        if (accountId == null) return resultList;
        List<AllergyIntolerance> allergies = [
            SELECT Id, Name, CreatedDate, LastModifiedDate,Generic__c,Status,
            Severity, OnsetStartDateTime,Allergy_Name__c,Reaction__c,	 
            Combine_allergy_and_Generic__c,Note__c,PatientId
            FROM AllergyIntolerance
            WHERE PatientId = :accountId
            ORDER BY OnsetStartDateTime DESC NULLS LAST LIMIT 10000];
        
        for (AllergyIntolerance a : allergies) {
            ContactMedicalDataWrappers.AllergyData d = new ContactMedicalDataWrappers.AllergyData();
            
            d.Id = a.Id;
            d.Name = (a.Combine_allergy_and_Generic__c != null ? a.Combine_allergy_and_Generic__c : '');
            d.CreatedDate = a.CreatedDate;
            d.LastModifiedDate = a.LastModifiedDate;
            d.Severity = a.Severity; 
            d.Onset_Date = a.OnsetStartDateTime != null ? a.OnsetStartDateTime.date() : null;
            d.Note = a.Note__c;
            d.generic = a.Generic__c;
            d.status = a.Status;
            d.Reaction = a.Reaction__c;
            if (a.PatientId != null) {
                d.Patient = a.PatientId; 
            } 
            resultList.add(d);
        }
        return resultList;
    }
/* ============================================================================
MEDICATION STATEMENT RECORDS
============================================================================ */
private static List<ContactMedicalDataWrappers.MedicationData> getMedicationStatementRecords(Id patientId) {
    List<ContactMedicalDataWrappers.MedicationData> resultList = new List<ContactMedicalDataWrappers.MedicationData>();
    if (patientId == null) return resultList;

    List<MedicationStatement> meds = [
        SELECT Id,
               OwnerId,
               Name,
               Status,
               Medication_Name__c,
               Dose__c,
               Frequency__c,
               Comments__c,
               CreatedDate,
               CreatedById,
               PatientId
        FROM MedicationStatement
        WHERE PatientId = :patientId
        ORDER BY CreatedDate DESC LIMIT 10000];

    for (MedicationStatement m : meds) {
        ContactMedicalDataWrappers.MedicationData d = new ContactMedicalDataWrappers.MedicationData();
        d.Id = m.Id;
        d.OwnerId = m.OwnerId;
        d.Name = m.Medication_Name__c;
        d.CreatedDate = m.CreatedDate;
        d.CreatedById = m.CreatedById;
        if (m.PatientId != null) {
            d.PatientId = m.PatientId;
        }
        d.Status = m.Status;
        d.Dose = m.Dose__c;
        d.Frequency = m.Frequency__c;
        d.Comments = m.Comments__c;
        resultList.add(d);
    }
    return resultList;
} 
/* ============================================================================
MEDICATION RECORDS
============================================================================ */
private static List<ContactMedicalDataWrappers.Medication> getMedicationRecords() {
    List<ContactMedicalDataWrappers.Medication> resultList = new List<ContactMedicalDataWrappers.Medication>();

    List<Medication> meds = [
        SELECT Id,
               OwnerId,
               Name,
               CreatedDate,
               CreatedById,
               Patient__c
        FROM Medication
        ORDER BY CreatedDate DESC LIMIT 10000];

    for (Medication m : meds) {
        ContactMedicalDataWrappers.Medication  d = new ContactMedicalDataWrappers.Medication();
        d.Id = m.Id;
        d.OwnerId = m.OwnerId;
        d.medication = m.Name;
        d.CreatedDate = m.CreatedDate;
        d.CreatedById = m.CreatedById;
        resultList.add(d);
    }
    return resultList;
}
 
    /* ============================================================================
INSURANCE PLANS (MEMBER PLAN)
============================================================================ */
    private static List<ContactMedicalDataWrappers.InsuranceData> getInsurancePlans(id PatientId) {
        List<ContactMedicalDataWrappers.InsuranceData> resultList = new List<ContactMedicalDataWrappers.InsuranceData>();
        if(patientId == null) return resultList;
        List<MemberPlan> memberPlans = [
            SELECT Id, OwnerId, IsDeleted, Name,CreatedDate, CreatedById,
            LastModifiedDate, LastModifiedById,
            medicalcoverage__Payer_Name__c, GroupNumber, MemberNumber,
            medicalcoverage__Subscriber_First_Name__c, 
            medicalcoverage__Subscriber_Last_Name__c,
            medicalcoverage__Subscriber_Birth_Date__c, 
            RelationshipToSubscriber, PrimarySecondaryTertiary,
            MemberId
            FROM MemberPlan
            WHERE MemberId = :patientId
            ORDER BY PrimarySecondaryTertiary ASC LIMIT 10000];
        
        for (MemberPlan mp : memberPlans) {
            ContactMedicalDataWrappers.InsuranceData d = new ContactMedicalDataWrappers.InsuranceData();
            d.id = mp.Id;
            d.OwnerId = mp.OwnerId;
            d.Name = mp.Name;
            d.CreatedDate = mp.CreatedDate;
            d.CreatedById = mp.CreatedById;
            d.LastModifiedDate = mp.LastModifiedDate;
            d.LastModifiedById = mp.LastModifiedById;
            d.providerName = mp.medicalcoverage__Payer_Name__c;
            d.GroupNumber = mp.GroupNumber;
            d.memberNumber = mp.MemberNumber;
            d.Subscriber_First_Name = mp.medicalcoverage__Subscriber_First_Name__c;
            d.Subscriber_Last_Name = mp.medicalcoverage__Subscriber_Last_Name__c;
            d.Subscriber_Birth_Date = mp.medicalcoverage__Subscriber_Birth_Date__c;
            d.RelationshipToSubscriber = mp.RelationshipToSubscriber;
            d.PrimarySecondaryTertiary = mp.PrimarySecondaryTertiary; 
            if(mp.MemberId != null){
                d.accountId = mp.MemberId;
            }
            resultList.add(d);
        }
        
        return resultList;
    }
    
    /* ============================================================================
GET HEALTHCARE FACILITY DATA 
============================================================================ */
    private static List<ContactMedicalDataWrappers.HealthcareFacility> getHealthcareFacilities(id patientId) {
        
        List<ContactMedicalDataWrappers.HealthcareFacility> resultList =
            new List<ContactMedicalDataWrappers.HealthcareFacility>();
        if(patientId == null) return resultList;
        
        List<HealthcareFacility> facilities = [
            SELECT Id,
            Name,
            AccountId,
            Fax_Number__c,
            Website__c,
            Phone__c,
            Email__c,
            Facility_type__c,
            Mailing_Address__c,
            CreatedById,
            CreatedDate,
            LastModifiedById,
            LastModifiedDate
            FROM HealthcareFacility
            WHERE AccountId = :patientId 
            ORDER BY CreatedDate DESC LIMIT 10000];
        
        for (HealthcareFacility f : facilities) {
            ContactMedicalDataWrappers.HealthcareFacility h =
                new ContactMedicalDataWrappers.HealthcareFacility();
            
            h.Id = f.Id;
            h.CreatedById = f.CreatedById;
            h.CreatedDate = f.CreatedDate;
            h.LastModifiedById = f.LastModifiedById;
            h.LastModifiedDate = f.LastModifiedDate;
            if (f.AccountId != null) {
                h.accountId = f.AccountId;
            }
            h.PractitionerName = f.Name != null ? f.Name : '';
            h.Mobile_Phone = f.Phone__c;
            h.Email = f.Email__c;
            h.faxNumber = f.Fax_Number__c;
            h.website = f.Website__c;
            h.facilityType = f.Facility_type__c  != null ? 
                f.Facility_type__c  : '';
            
            h.address = new ContactMedicalDataWrappers.HealthcareFacilityaddress();
            if(f.Mailing_Address__c != null) {
                h.address.street = f.Mailing_Address__c.getStreet() != null ? 
                    f.Mailing_Address__c.getStreet() : '';
                h.address.city = f.Mailing_Address__c.getCity() != null ? 
                    f.Mailing_Address__c.getCity() : '';
                h.address.state = f.Mailing_Address__c.getState() != null ? 
                    MedicalRecordsUpdateAPI.getStateName(f.Mailing_Address__c.getState()) : '';
                h.address.postalCode = f.Mailing_Address__c.getPostalCode() != null ? 
                    f.Mailing_Address__c.getPostalCode() : '';
            }
            
            resultList.add(h);
        }
        
        return resultList;
    }
    /* ============================================================================ 
GET HEALTHCARE PROFESSIONALS DATA
============================================================================ */
    private static List<ContactMedicalDataWrappers.HealthcareProfessionals> getHealthcareProfessionals(id patientId) {
        List<ContactMedicalDataWrappers.HealthcareProfessionals> resultList = 
            new List<ContactMedicalDataWrappers.HealthcareProfessionals>();
        if(patientId == null) return resultList;
        
        List<HealthcarePractitionerFacility> professionals = [
            SELECT Id,
            Name,
            AccountId,
            Specialty__c,
            Fax_Number__c,
            Website__c,
            PractitionerId,
            Practitioner.Name,
            Phone__c,
            Email__c,
            Address__c,
            Address__Street__s, Address__City__s,Address__StateCode__s,Address__PostalCode__s,Address__CountryCode__s,
            CreatedById,
            CreatedDate,
            LastModifiedById,
            LastModifiedDate,
            OwnerId
            FROM HealthcarePractitionerFacility
            WHERE AccountId = :patientId 
            ORDER BY CreatedDate DESC LIMIT 10000];
        
        for (HealthcarePractitionerFacility p : professionals) {
            ContactMedicalDataWrappers.HealthcareProfessionals hp = 
                new ContactMedicalDataWrappers.HealthcareProfessionals();
            
            hp.Id = p.Id;
            hp.OwnerId = p.OwnerId;
            hp.CreatedById = p.CreatedById;
            hp.CreatedDate = p.CreatedDate;
            hp.LastModifiedById = p.LastModifiedById;
            hp.LastModifiedDate = p.LastModifiedDate;
            hp.Specialty = p.Specialty__c;
            hp.Email = p.Email__c;
            hp.phone = p.Phone__c;
            hp.faxNumber = p.Fax_Number__c;
            hp.website = p.Website__c;
            if(p.AccountId != null){
                hp.accountId = p.AccountId; 
            }
            
            hp.healthcareProfessionalName = p.Name != null && p.Name != null ? 
                p.Name : '';
            
            hp.address = new ContactMedicalDataWrappers.HealthcareProfessionalsaddress();
            if(p.Address__c != null) {
                hp.address.street = p.Address__Street__s != null ? p.Address__Street__s : '';
                hp.address.city = p.Address__City__s != null ? p.Address__City__s : '';
                hp.address.state = p.Address__StateCode__s != null ? 
                    MedicalRecordsUpdateAPI.getStateName(p.Address__StateCode__s) : '';
                hp.address.postalCode = p.Address__PostalCode__s != null ? 
                    p.Address__PostalCode__s : '';
                hp.address.country = p.Address__CountryCode__s != null ? 
                    p.Address__CountryCode__s : '';
            }
            
            resultList.add(hp);
        }
        
        return resultList;
    }
    /* ============================================================================
GET PERSONAL CONTACTS 
============================================================================ */
  private static List<ContactMedicalDataWrappers.PersonalContacts> getPersonalContactsOnly(Id personAccountId) {
        
    List<ContactMedicalDataWrappers.PersonalContacts> resultList =
        new List<ContactMedicalDataWrappers.PersonalContacts>();
    
    if (personAccountId == null) {
        return resultList;
    }
    
    try {
        List<Contact> personalContactsList = [
            SELECT 
            Id, 
            OwnerId, 
            AccountId, 
            FirstName, 
            LastName, 
            Email,
            Emergency_Contact_Relationship__c,
            MobilePhone, 
            HomePhone,
            MailingStreet, 
            MailingCity, 
            MailingState, 
            MailingStateCode,
            MailingPostalCode, 
            MailingCountry,
            Account__c,
            Description,
            Emergency_Contact__c,
            Is_PHI_Authorized__c,
            Is_Healthcare_Proxy__c,
            ADT_Contact__c,
            Authorized_Representative__c,
            CreatedById, 
            CreatedDate,
            LastModifiedById, 
            LastModifiedDate
            FROM Contact
            WHERE Account__c = :personAccountId
            ORDER BY CreatedDate DESC LIMIT 10000];
        
        for (Contact con : personalContactsList) {
            ContactMedicalDataWrappers.PersonalContacts pc =
                new ContactMedicalDataWrappers.PersonalContacts();
            
            pc.Id = con.Id;
            pc.OwnerId = con.OwnerId;
            if(con.Account__c != null){
                pc.accountId = con.Account__c;
            }
            pc.FirstName = con.FirstName;
            pc.LastName = con.LastName;
            pc.Email = con.Email;
            pc.EmergencyContactRelationship = con.Emergency_Contact_Relationship__c;
            pc.MobilePhone = con.MobilePhone;
            pc.HomePhone = con.HomePhone;
            pc.MailingStreet = con.MailingStreet;
            pc.MailingCity = con.MailingCity;
            pc.MailingState = con.MailingState;
            pc.MailingStateCode = con.MailingStateCode;
            pc.MailingPostalCode = con.MailingPostalCode;
            pc.MailingCountry = con.MailingCountry;
            pc.Notes = con.Description;
            pc.EmergencyContact = con.Emergency_Contact__c;
            pc.IsPHIAuthorized = con.Is_PHI_Authorized__c;
            pc.IsHealthcareProxy = con.Is_Healthcare_Proxy__c;
            pc.adt_contact = con.ADT_Contact__c;
            pc.authorized_representative = con.Authorized_Representative__c;
            pc.CreatedById = con.CreatedById;
            pc.CreatedDate = con.CreatedDate;
            pc.LastModifiedById = con.LastModifiedById;
            pc.LastModifiedDate = con.LastModifiedDate;
            
            resultList.add(pc);
        }
        
    } catch (Exception e) {
        System.debug('### ERROR in getPersonalContactsOnly: ' + e.getMessage());
    }
    
    return resultList;
}
    /* ============================================================================
UTIL
============================================================================ */
    private static String cleanPhoneNumber(String phone) {
        return String.isBlank(phone) ? phone : phone.replaceAll('[^0-9]', '');
    }
}