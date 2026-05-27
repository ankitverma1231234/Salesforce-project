public with sharing class MetriportPatientService {

    /***************
     * Data Classes
     ***************/
    public class PatientRequest {
        public String firstName;
        public String lastName;
        public String dob;
        public String genderAtBirth;
        public String externalId;
        public List<Address> address;
        public List<Contact> contact;
    }

    public class Address {
        public String addressLine1;
        public String addressLine2;
        public String city;
        public String state;
        public String zip;
    }

    public class Contact {
        public String phone;
        public String email;
    }

    public class PatientResponse {
        public String id;
    }

    /***************
     * Public Method
     ***************/
    @future(callout=true)
    public static void createMetriportPatients(Map<Id, String> accountIdToExternalId) {
        if (accountIdToExternalId.isEmpty()) return;

        // Load metadata
        Metriport_Config__mdt meta = [SELECT API_Key__c, Base_URL__c,facilityId__c FROM Metriport_Config__mdt Where Active__c = true LIMIT 1];
        String apiKey = meta.API_Key__c;
        String baseUrl = meta.Base_URL__c;
        String facilityId = meta.facilityId__c;

        List<Account> accounts = [
            SELECT Id, FirstName, LastName,Maiden_Name__pc, Date_of_Birth__pc, PersonEmail, PersonMobilePhone,PersonGenderIdentity,
                   PersonMailingStreet, PersonMailingCity,PersonOtherStreet, PersonMailingStateCode, PersonMailingPostalCode, PersonMailingCountry,Biological_Sex_at_Birth__c
            FROM Account
            WHERE Id IN :accountIdToExternalId.keySet()
        ];

        for (Account acc : accounts) {
            try {
				

                PatientRequest req = new PatientRequest();
                //req.facilityId = '019ac5bc-ad1e-7031-8f34-362e5ffea6a0';
                req.firstName = acc.FirstName;
               if (String.isNotBlank(acc.Maiden_Name__pc)) {
                    req.lastName = acc.LastName + ',' + acc.Maiden_Name__pc;
                } else {
                    req.lastName = acc.LastName;
                }
                String dob = '';
                if (acc.Date_of_Birth__pc != null && acc.Date_of_Birth__pc.year() >= 1900) {
                    Integer month = acc.Date_of_Birth__pc.month();
                    Integer day = acc.Date_of_Birth__pc.day();
                    String monthStr = month < 10 ? '0' + month : String.valueOf(month);
                    String dayStr = day < 10 ? '0' + day : String.valueOf(day);
                    req.dob = acc.Date_of_Birth__pc.year() + '-' + monthStr + '-' + dayStr;
                } else {
                    req.dob = ''; // send empty if unknown or invalid
                }


          		String gender = acc.Biological_Sex_at_Birth__c != null ? acc.Biological_Sex_at_Birth__c.toLowerCase() : '';
				if (gender == 'male') {
   			 		gender = 'M';
				} else if (gender == 'female') {
    			gender = 'F';
				} else if (gender == 'other') {
   			 	gender = 'O';
				} else {
    			gender = 'U'; // unknown or unmapped
				}
				req.genderAtBirth = gender;
                
                // Contact
                req.contact = new List<Contact>();
                Contact c = new Contact();
                c.email = acc.PersonEmail;
                c.phone = acc.PersonMobilePhone;
                req.contact.add(c);

                // Address
                req.address = new List<Address>();
                Address addr = new Address();
                addr.addressLine1 = acc.PersonMailingStreet != null ? acc.PersonMailingStreet : '';
                addr.addressLine2 = acc.PersonOtherStreet != null ? acc.PersonOtherStreet : '';
                addr.city = acc.PersonMailingCity != null ? acc.PersonMailingCity : '';
                addr.state = acc.PersonMailingStateCode != null ? acc.PersonMailingStateCode : '';
                addr.zip = acc.PersonMailingPostalCode != null ? acc.PersonMailingPostalCode : '';
                req.address.add(addr);

                req.externalId = acc.Id;

				//String facilityId = '019c03a9-17ed-7cc9-826b-dfed2ab3666d';
                
                
                String createPatientEndpoint = baseUrl + '/medical/v1/patient?facilityId=' + EncodingUtil.urlEncode(facilityId, 'UTF-8');

                // HTTP Callout
                Http http = new Http();
                HttpRequest request = new HttpRequest();
                request.setEndpoint(createPatientEndpoint); 
                request.setMethod('POST');
                request.setHeader('Content-Type', 'application/json');
                request.setHeader('x-api-key', apiKey); 
                request.setBody(JSON.serialize(req));

                HttpResponse response = http.send(request);

                if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
                    PatientResponse pr = (PatientResponse) JSON.deserialize(response.getBody(), PatientResponse.class);
                    System.debug('Metriport Patient created with ID: ' + pr.id);

                     Account updateAcc = new Account(Id = acc.Id, Metriport_Patient_Id__c = pr.id);
                     update updateAcc;

                } else {
                    System.debug('Metriport API error: Status=' + response.getStatusCode() + ' Body=' + response.getBody());
                }

            } catch (Exception ex) {
                System.debug('Exception while calling Metriport API: ' + ex.getMessage());
            }
        }
    }
}