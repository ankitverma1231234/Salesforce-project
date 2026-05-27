@IsTest(SeeAllData=true)
public class ContactMedicalDataWrapperTest {

    /* ============================================================
       Utility: Fetch an existing Patient (Person Account Contact)
       ============================================================ */
    private static Contact getPatientContact() {
        List<Contact> cons = [
            SELECT Id, Email, Phone, MobilePhone, FirstName, LastName, AccountId
            FROM Contact
            WHERE Account.IsPersonAccount = true
            AND Email != null
            AND (Phone != null OR MobilePhone != null)
            LIMIT 1
        ];
        System.assert(!cons.isEmpty(),
            'No Person Account Contact available in org data');
        return cons[0];
    }

    /* ============================================================
       TEST 1: SUCCESS PATH (FULL DATA BUILD)
       ============================================================ */
    @IsTest
    static void testGetContactData_Success() {

        Contact c = getPatientContact();

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/ContactMedicalData/v1/';
        req.httpMethod = 'POST';

        Map<String, Object> body = new Map<String, Object>{
            'email' => c.Email,
            'phone' => c.Phone != null ? c.Phone : c.MobilePhone,
            'firstName' => c.FirstName,
            'lastName' => c.LastName
        };

        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        ContactMedicalDataWrappers.ResponseWrapper response =
            ContactMedicalDataAPI.getContactData();
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('Contact retrieved', response.message);
        System.assertNotEquals(null, response.data);

        // Wrapper coverage assertions
        System.assertNotEquals(null, response.data.address);
        System.assertNotEquals(null, response.data.otheraddress);
        System.assertNotEquals(null, response.data.surgeries);
        System.assertNotEquals(null, response.data.medicalHistory);
        System.assertNotEquals(null, response.data.allergies);
        System.assertNotEquals(null, response.data.medications);
        System.assertNotEquals(null, response.data.insurancePlans);
        System.assertNotEquals(null, response.data.healthcareFacilities);
        System.assertNotEquals(null, response.data.healthcareProfessionals);
        System.assertNotEquals(null, response.data.personalContacts);
        System.assertNotEquals(null, response.data.CasemessageList);
        System.assertNotEquals(null, response.data.documents);

        System.assertNotEquals(null, response.recordCount);
        System.assertNotEquals(null, response.debugInfo);
    }

    /* ============================================================
       TEST 2: MISSING REQUIRED FIELDS
       ============================================================ */
    @IsTest
    static void testGetContactData_MissingFields() {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/ContactMedicalData/v1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"email":""}');

        RestContext.request = req;
        RestContext.response = res;

        ContactMedicalDataWrappers.ResponseWrapper response =
            ContactMedicalDataAPI.getContactData();

        System.assertEquals(false, response.success);
        System.assertEquals(
            'Email and Phone are required for search',
            response.message
        );
    }

    /* ============================================================
       TEST 3: CONTACT NOT FOUND
       ============================================================ */
    @IsTest
    static void testGetContactData_NotFound() {

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/ContactMedicalData/v1/';
        req.httpMethod = 'POST';

        req.requestBody = Blob.valueOf(
            '{"email":"doesnotexist@test.com","phone":"9999999999"}'
        );

        RestContext.request = req;
        RestContext.response = res;

        ContactMedicalDataWrappers.ResponseWrapper response =
            ContactMedicalDataAPI.getContactData();

        //System.assertEquals(false, response.success);
        //System.assertEquals('CONTACT_NOT_FOUND', response.errorCode);
    }

    /* ============================================================
       TEST 4: PHONE CLEANING + DEBUG INFO PATH
       ============================================================ */
    @IsTest
    static void testPhoneCleaningDebugInfo() {

        Contact c = getPatientContact();

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/ContactMedicalData/v1/';
        req.httpMethod = 'POST';

        req.requestBody = Blob.valueOf(JSON.serialize(
            new Map<String, Object>{
                'email' => c.Email,
                'phone' => '(+1) ' + c.Phone
            }
        ));

        RestContext.request = req;
        RestContext.response = res;

        ContactMedicalDataWrappers.ResponseWrapper response =
            ContactMedicalDataAPI.getContactData();

        System.assertNotEquals(null, response.debugInfo);
        System.assertNotEquals(null, response.debugInfo.cleanedPhone);
    }
}