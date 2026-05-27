/**
* Wrapper classes for ContactMedicalDataAPI
* Contains all response and data structures
*/
global class ContactMedicalDataWrappers {
    
    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public String errorCode;
        public String errorDetails;
        public String errorStackTrace;
        public String searchedEmail;
        public String searchedPhone;
        public String searchedFirstName;
        public String searchedLastName;
        public ContactData data;
        public RecordCount recordCount;
        public DebugInfo debugInfo;
    }
    
    global class DebugInfo {
        public String originalPhone;
        public String trimmedPhone;
        public String cleanedPhone;
    }
    
    global class RecordCount {
        public Integer surgeries;
        public Integer medicalHistory;
        public Integer allergies;
        public Integer medications;
        public Integer insurancePlans;
        public Integer healthcareFacilitiesCount;
        public Integer HealthcareProfessionalCount;
        public Integer personalContactsCount;
        public Integer messageCaseCount;
        public Integer documentsCount;
    }
    
    global class ContactData {
        public String contactId;
        public String personAccountId;
        public Boolean isPersonAccount;
        public String firstName;
        public String lastName;
        public String fullName;
        public String email;
        public String phone;
        public String mobilePhone;
        public Date birthdate;
        public String accountId;
        public String accountName;
        public Datetime createdDate;
        public Datetime lastModifiedDate;
        public Date Date_of_Birth;
        public Date Sign_up_date;
        public String maidenname;
        public Date Renewal_date;
        public String status;
        public AddressData address;
        public OtherAddressData otheraddress;
        public String Work_Phone;
        public Decimal Height_in_inches;
        public Decimal Weight_in_pounds;
        public String preferredContactMethod;
        public String preferredname;
        public String preferredLanguage;
        public String salutation;
        public String suffix;
        public String genderIdentity;
        public String accountFax;
        public String additionalEmail;
        public String occupation;
        public String maritalStatus;
        public String biologicalSexAtBirth;
        public String sexualOrientation;
        public String race;
        public String ethnicity;
        public String livingSituation;
        public boolean Consent_to_Call;
        public boolean Consent_to_Text; 
        public boolean communicationConsent; 
        public String Summary;
        public String Medical_History_Notes;
        public List<SurgeryData> surgeries;
        public List<MedicalHistoryData> medicalHistory;
        public List<AllergyData> allergies;
        public List<MedicationData> medications;  
        public List<InsuranceData> insurancePlans;
        public List<ContactMedicalDataWrappers.HealthcareFacility> healthcareFacilities;
        public List<HealthcareProfessionals> healthcareProfessionals;
        public List<PersonalContacts> personalContacts;
        public List<Medication> medicationsList;
        public List<CaseData> CasemessageList;
        public List<DocumentData> documents;
    }
    
    global class AddressData {
        public String street;
        public String city;
        public String state;
        public String postalCode;
        public String country;
    }
    
    global class OtherAddressData {
        public String street;
        public String city;
        public String state;
        public String postalCode;
        public String country;
    }
    global class CaseData {
        public String Id;
        public String CaseNumber;
        public String OwnerId;
        public String Subject;
        public String Status;
        public String Priority;
        public String Type;
        public String Reason;
        public String Origin;
        public String Description;
        public Datetime ClosedDate;
        public Datetime CreatedDate;
        public String CreatedById;
        public Datetime LastModifiedDate;
        public String LastModifiedById;
        public String AccountId;
        public String ContactId;
        public String ParentId;
        public String SuppliedEmail;
        public String SuppliedPhone;
    }
    
    global class HealthcareFacilityaddress {
        public String street;
        public String city;
        public String state;
        public String postalCode;
        public String country;
    }
    global class HealthcareProfessionalsaddress {
        public String street;
        public String city;
        public String state;
        public String postalCode;
        public String country;
    }
    
    global class SurgeryData {
        public String Id;
        public String name;
        public String OwnerId;
        public Boolean IsDeleted;
        public Date Surgery_Date;
        public String Note;
        public String Patient;
        public String Account;
        public String patientName;
        public String patientEmail;
        public String patientPhone;
        public Datetime createdDate;
        public Datetime lastModifiedDate;
        public Date LastActivityDate;
        public String LastModifiedById;
        public string CreatedById;
        public String status;
    }
    
    global class MedicalHistoryData {
        public String Id;
        public String name;
        public String OwnerId;
        public Boolean IsDeleted;
        public String Medical_Problem;
        public String Specify_Cancer_Type;
        public Datetime Onset_Date;
        public String Note;
        public String Patient;
        public String patientAccountId;
        public String patientName;
        public String patientEmail;
        public String patientPhone;
        public Datetime lastModifiedDate;
        public Datetime CreatedDate;         
        public String CreatedById;           
        public Date LastActivityDate;
        public String LastModifiedById;
        public String status;
    }
    
    global class AllergyData {
        public String Id;                    
        public String OwnerId;              
        public Boolean IsDeleted;            
        public String Name;                 
        public Datetime CreatedDate;        
        public String CreatedById;          
        public Datetime LastModifiedDate;     
        public String LastModifiedById;   
        public String Severity;
        public String Reaction;          
        public Date Onset_Date;           
        public String Note; 
        public String generic;
        public String Patient;            
        public String PatientAccountId;
        public String PatientName;
        public String PatientEmail;
        public String PatientPhone;
        public Date LastActivityDate;
        public String status;
    }
    
    global class MedicationData {
        public String Id;
        public String OwnerId;
        public Boolean IsDeleted;
        public String Name;
        public Datetime CreatedDate;
        public String CreatedById;
        public Datetime LastModifiedDate;
        public String PatientId;
        public String Status;
        public String medication;
        public String Dose;
        public String Frequency;
        public String Reason;
        public String Comments;
        public String PatientAccountId;
    }
    global class InsuranceData {
        public String id;
        public String OwnerId;
        public String providerName;
        public String GroupNumber;
        public String memberNumber;
        public String Subscriber_First_Name;
        public String Subscriber_Last_Name;
        public Datetime   Subscriber_Birth_Date;
        public String RelationshipToSubscriber;
        public String PrimarySecondaryTertiary;
        public String Name;
        public Id accountId;
        public String LastModifiedById;
        public Datetime LastModifiedDate;
        public String CreatedById;
        public Datetime CreatedDate;
    } 
    
    global class HealthcareFacility {
        public String Id;
        public String OwnerId;
        public Id accountId;
        public String CreatedById;
        public Datetime CreatedDate;
        public String LastModifiedById;
        public Datetime LastModifiedDate;
        public String PractitionerName;
        public String website;
        public String facilityType;
        public HealthcareFacilityaddress address { get; set; }
        public String Mobile_Phone;
        public String faxNumber;
        public String Email;
    }
    global class HealthcareProfessionals {
        public String Id;
        public String OwnerId;
        public Id accountId;
        public String CreatedById;
        public Datetime CreatedDate;
        public String LastModifiedById;
        public Datetime LastModifiedDate;
        public String healthcareProfessionalName;
        public String Specialty;
        public String faxNumber;
        public String Email;
        public String website;
        public String phone;
        public HealthcareProfessionalsaddress address { get; set; }
    }
    global class PersonalContacts {
        public String Id;
        public String OwnerId;
        public Id accountId;
        public String FirstName ;
        public String LastName ;
        public String Email; 
        public String EmergencyContactRelationship;
        public String MobilePhone;
        public String HomePhone;
        public String MailingStreet;
        public String MailingCity;
        public String MailingState;
        public String MailingStateCode;
        public String MailingPostalCode;
        public String MailingCountry;
        public String Notes;
        public Boolean EmergencyContact;
        public Boolean IsPHIAuthorized;
        public Boolean adt_contact;
        public Boolean authorized_representative;
        public Boolean IsHealthcareProxy;
        public String CreatedById;
        public Datetime CreatedDate;
        public String LastModifiedById;
        public Datetime LastModifiedDate;
    } 
    global class Medication {
        public String Id; 
        public String medication;
        public String CreatedById;
        public Datetime CreatedDate;
        public String OwnerId;
    }  
    public class DocumentData {
        public String Id;
        public String ContentDocumentId;
        public String LinkedEntityId;
        public String Title;
        public String FileType;
        public String FileExtension;
        public Integer ContentSize;
        public Date CreatedDate;
        public String CreatedById;
        public Datetime LastModifiedDate;
        public String LastModifiedById;
        public String OwnerId;
        public String LatestPublishedVersionId;
        public String VersionNumber;
        public String PathOnClient;
        public String ShareType;
        public String Visibility;
        public String PublicUrl;
        public String Description;
        public String Organization_Name;
    }
}