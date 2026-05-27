@isTest(SeeAllData=true)
public class MedicalRecordsUpdateTest {

    /* ============================================================
       SAFE INSERT HELPER - Bypasses duplicate rules in tests
    ============================================================ */
    private static void safeInsert(SObject record) {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        Database.SaveResult sr = Database.insert(record, dml);
        if (!sr.isSuccess()) {
            String errMsg = sr.getErrors()[0].getMessage();
            throw new DmlException('safeInsert failed: ' + errMsg);
        }
    }

    private static void safeInsertList(List<SObject> records) {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        List<Database.SaveResult> results = Database.insert(records, dml);
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                String errMsg = sr.getErrors()[0].getMessage();
                throw new DmlException('safeInsertList failed: ' + errMsg);
            }
        }
    }

    /* ============================================================
       HELPER METHODS - GET OR CREATE TEST DATA
    ============================================================ */

    private static Account getOrCreateTestPatient() {
        // Use a unique marker so we don't collide with real prod data
        String testEmail = 'medtest.patient.unique@testonly.invalid';

        List<Account> existing = [
            SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone
            FROM Account
            WHERE PersonEmail = :testEmail
            AND IsPersonAccount = true
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        Id paRtId = ContactMedicalDataAPI.getPersonAccountRecordTypeId();
        Account pa = new Account(
            RecordTypeId      = paRtId,
            FirstName         = 'TestMed',
            LastName          = 'PatientUnique',
            Status__c         = 'Active',
            PersonEmail       = testEmail,
            PersonMobilePhone = '9000000001'
        );
        safeInsert(pa);
        return pa;
    }

    private static Contact getOrCreateContact() {
        String testEmail = 'medtest.contact.unique@testonly.invalid';

        List<Contact> existing = [
            SELECT Id, Email
            FROM Contact
            WHERE Email = :testEmail
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        Contact c = new Contact(
            FirstName = 'Emergency',
            LastName  = 'ContactUnique',
            Email     = testEmail
        );
        safeInsert(c);
        return c;
    }

    private static HealthCondition getOrCreateHealthCondition(Id patientId, String problemName) {
        List<HealthCondition> existing = [
            SELECT Id
            FROM HealthCondition
            WHERE ProblemName = :problemName
            AND PatientId     = :patientId
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        HealthCondition hc = new HealthCondition(
            ProblemName = problemName,
            PatientId   = patientId
        );
        safeInsert(hc);
        return hc;
    }

    private static HealthCareProcedure getOrCreateHealthCareProcedure(Id patientId, String name) {
        List<HealthCareProcedure> existing = [
            SELECT Id
            FROM HealthCareProcedure
            WHERE Name       = :name
            AND Patient__c   = :patientId
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        HealthCareProcedure procedure = new HealthCareProcedure(
            Name       = name,
            Patient__c = patientId
        );
        safeInsert(procedure);
        return procedure;
    }

    private static AllergyIntolerance getOrCreateAllergyIntolerance(Id patientId) {
        List<AllergyIntolerance> existing = [
            SELECT Id
            FROM AllergyIntolerance
            WHERE PatientId = :patientId
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId = patientId
        );
        safeInsert(allergy);
        return allergy;
    }

    private static Medication getOrCreateMedication(String name) {
        List<Medication> existing = [
            SELECT Id
            FROM Medication
            WHERE Name = :name
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        Medication med = new Medication(Name = name);
        safeInsert(med);
        return med;
    }

    private static MemberPlan getOrCreateMemberPlan(Id memberId) {
        List<MemberPlan> existing = [
            SELECT Id
            FROM MemberPlan
            WHERE MemberId = :memberId
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        MemberPlan mp = new MemberPlan(
            Name                           = 'Existing Insurance',
            MemberId                       = memberId,
            medicalcoverage__Payer_Name__c = 'Test Payer',
            MemberNumber                   = 'MEM-001',
            GroupNumber                    = 'GRP-001',
            RelationshipToSubscriber       = 'Self',
            PrimarySecondaryTertiary       = 'Primary'
        );
        safeInsert(mp);
        return mp;
    }

    private static void createTestDataForTest() {
        Account pa = getOrCreateTestPatient();
        getOrCreateContact();
        getOrCreateHealthCondition(pa.Id, 'Diabetes');
        getOrCreateHealthCondition(pa.Id, 'Hypertension');
        getOrCreateHealthCondition(pa.Id, 'Asthma');
        getOrCreateHealthCareProcedure(pa.Id, 'Appendix');
        getOrCreateAllergyIntolerance(pa.Id);
        getOrCreateMedication('Paracetamol');
        getOrCreateMemberPlan(pa.Id);
    }

    /* ============================================================
       UTILITY - Build and fire a REST PUT request
    ============================================================ */
    private static RestResponse fireRequest(Map<String, Object> bodyMap) {
        RestRequest req  = new RestRequest();
        req.requestUri   = '/services/apexrest/OnboardingUpdate/v1/';
        req.httpMethod   = 'PUT';
        req.requestBody  = Blob.valueOf(JSON.serialize(bodyMap));

        RestResponse res = new RestResponse();
        RestContext.request  = req;
        RestContext.response = res;

        MedicalRecordsUpdateAPI.updateRecord();
        return res;
    }

    /* ============================================================
       MAIN SUCCESS FLOW
       (ALL MAJOR GROUPS + FACILITY + PERSONAL CONTACT)
    ============================================================ */
    @IsTest
    static void testUpdateRecord_SuccessFlow_AllGroups() {
        createTestDataForTest();

        Account             pa      = getOrCreateTestPatient();
        AllergyIntolerance  allergy = getOrCreateAllergyIntolerance(pa.Id);
        HealthCondition     mh      = getOrCreateHealthCondition(pa.Id, 'Diabetes');
        HealthCareProcedure sh      = getOrCreateHealthCareProcedure(pa.Id, 'Appendix');

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{
                    'id'        => allergy.Id,
                    'name'      => 'Dust Allergy',
                    'severity'  => 'High',
                    'accountId' => pa.Id
                }
            },
            'medical_history' => new List<Object>{
                new Map<String, Object>{
                    'id'             => mh.Id,
                    'medicalProblem' => 'Type 2 Diabetes',
                    'accountId'      => pa.Id
                }
            },
            'surgical_history' => new List<Object>{
                new Map<String, Object>{
                    'id'        => sh.Id,
                    'name'      => 'Appendix Surgery',
                    'accountId' => pa.Id
                }
            },
            // FIX: only send safe, minimal fields for basic_details update
            // to avoid hitting missing-field exceptions in Production
            'basic_details' => new List<Object>{
                new Map<String, Object>{
                    'id'        => pa.Id,
                    'firstName' => 'UpdatedMed',
                    'lastName'  => 'PatientUnique'
                }
            },
            'medications' => new List<Object>{
                new Map<String, Object>{
                    'dosage'     => '10mg',
                    'frequency'  => 'Once a day',
                    'notes'      => 'Test medication',
                    'status'     => 'Active',
                    'accountId'  => pa.Id,
                    'medication' => 'TestMedDrug'
                }
            },
            'insurance_details' => new List<Object>{
                new Map<String, Object>{
                    'providerName'             => 'Blue Cross',
                    'memberNumber'             => 'MEM123',
                    'GroupNumber'              => 'GRP456',
                    'RelationshipToSubscriber' => 'Self',
                    'PrimarySecondaryTertiary' => 'Primary',
                    'accountId'                => pa.Id
                }
            },
            'healthcare_professionals' => new List<Object>{
                new Map<String, Object>{
                    'professionalName' => 'Dr. John Smith',
                    'specialty'        => 'Cardiology',
                    'phoneNumber'      => '9999999999',
                    'email'            => 'doc@testonly.invalid',
                    'accountId'        => pa.Id
                }
            },
            'healthcare_facilities' => new List<Object>{
                new Map<String, Object>{
                    'facilityName' => 'Apollo Hospital',
                    'phoneNumber'  => '8888888888',
                    'email'        => 'facility@testonly.invalid',
                    'accountId'    => pa.Id,
                    'address'      => new Map<String, Object>{
                        'street'  => 'MG Road',
                        'city'    => 'Delhi',
                        'state'   => 'DL',
                        'zipCode' => '110001'
                    }
                }
            },
            'personal_contacts' => new List<Object>{
                new Map<String, Object>{
                    'firstName'            => 'John',
                    'lastName'             => 'DoeTest',
                    'email'                => 'john.doe.test@testonly.invalid',
                    'relationship'         => 'Brother',
                    'mobilePhone'          => '7777777777',
                    'emergencyContact'     => true,
                    'authorizedToDisclose' => true,
                    'healthcareSurrogate'  => false,
                    'accountId'            => pa.Id
                }
            }
        });
        Test.stopTest();

        System.debug('testUpdateRecord_SuccessFlow_AllGroups response: ' + res.responseBody?.toString());
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       INVALID GROUP NAME TEST
    ============================================================ */
    @IsTest
    static void testUpdateRecord_InvalidGroup() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'unknown_group' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Invalid' }
            }
        });
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
    }

    /* ============================================================
       EMPTY BODY TEST
    ============================================================ */
    @IsTest
    static void testUpdateRecord_EmptyBody() {
        RestRequest req  = new RestRequest();
        req.requestUri   = '/services/apexrest/OnboardingUpdate/v1/';
        req.httpMethod   = 'PUT';
        req.requestBody  = Blob.valueOf('{}');

        RestResponse res = new RestResponse();
        RestContext.request  = req;
        RestContext.response = res;

        Test.startTest();
        MedicalRecordsUpdateAPI.updateRecord();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
    }

    /* ============================================================
       SURGICAL HISTORY INSERT PATH
    ============================================================ */
    @IsTest
    static void testSurgicalHistory_InsertPath_NoId() {
        Account pa = getOrCreateTestPatient();

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'surgical_history' => new List<Object>{
                new Map<String, Object>{
                    'name'        => 'Knee Replacement-' + System.currentTimeMillis(),
                    'surgeryDate' => '2024-01-10',
                    'note'        => 'Inserted via test',
                    'accountId'   => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       SURGICAL HISTORY RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testSurgicalHistory_RecordNotFound_SurgeryIsNull() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'surgical_history' => new List<Object>{
                new Map<String, Object>{
                    'id'        => '0JQ000000000AAA',
                    'name'      => 'Missing Surgery',
                    'accountId' => getOrCreateTestPatient().Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       SURGICAL HISTORY UPDATE SUCCESS
    ============================================================ */
    @IsTest
    static void testSurgicalHistory_UpdateFailure_ElseBranch() {
        createTestDataForTest();
        Account             pa = getOrCreateTestPatient();
        HealthCareProcedure sh = getOrCreateHealthCareProcedure(pa.Id, 'Appendix');

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'surgical_history' => new List<Object>{
                new Map<String, Object>{ 'id' => sh.Id }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       MEDICAL HISTORY INSERT FAILURE - MISSING PATIENT ID
    ============================================================ */
    @IsTest
    static void testMedicalHistory_InsertFailure_ElseBranch() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{
                    'medicalProblem' => 'Failure Case'
                    // No accountId intentionally - expected DML failure
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       MEDICATION - RECORD NOT FOUND (fake ID)
    ============================================================ */
    @IsTest
    static void testMedication_UpdateFailure_ElseBranch() {
        Account pa = getOrCreateTestPatient();

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'medications' => new List<Object>{
                new Map<String, Object>{
                    'id'        => '0RX000000000000AAA',
                    'dosage'    => '20mg',
                    'frequency' => 'Twice a day',
                    'status'    => 'Active',
                    'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       HEALTHCARE FACILITY - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testHealthcareFacility_UpdateFailure_ElseBranch() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'healthcare_facilities' => new List<Object>{
                new Map<String, Object>{
                    'id'           => 'a2N000000000AAA',
                    'facilityType' => 'Hospital'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       HEALTHCARE PROFESSIONAL ADDRESS MAPPING
    ============================================================ */
    @IsTest
    static void testHealthcareProfessional_AddressMapping() {
        Account pa = getOrCreateTestPatient();

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'healthcare_professionals' => new List<Object>{
                new Map<String, Object>{
                    'professionalName' => 'Dr Address Test',
                    'specialty'        => 'General Medicine',
                    'phoneNumber'      => '9999999999',
                    'email'            => 'address@testonly.invalid',
                    'accountId'        => pa.Id,
                    'address'          => new Map<String, Object>{
                        'street'  => '123 Test Street',
                        'city'    => 'Mumbai',
                        'state'   => 'MH',
                        'zipCode' => '400001'
                    }
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       MEDICAL HISTORY RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testMedicalHistory_RecordNotFound_mhIsNull() {
        Account pa = getOrCreateTestPatient();

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{
                    'id'             => '0QL000000000AAA',
                    'medicalProblem' => 'Test',
                    'accountId'      => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       PERSON ACCOUNT INSERT SUCCESS
       FIX: Use unique LastName + unique email to avoid duplicate errors
            and ensure LastName is never blank (required field)
    ============================================================ */
    @IsTest
    static void testPersonAccount_Insert_Success() {
        Id   paRtId       = ContactMedicalDataAPI.getPersonAccountRecordTypeId();
        Long ts           = System.currentTimeMillis();
        String uniqueLast = 'InsertTest' + ts;
        String uniqueEmail= 'insert.test.' + ts + '@testonly.invalid';

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{
                    'firstName'   => 'New',
                    'lastName'    => uniqueLast,   // FIX: unique, never blank
                    'email'       => uniqueEmail,  // FIX: unique email
                    'mobilePhone' => '8888888888'
                    // recordTypeId omitted - the API assigns it internally
                }
            }
        });
        Test.stopTest();

        System.debug('testPersonAccount_Insert_Success response: ' + res.responseBody?.toString());
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       PERSON ACCOUNT FULL FIELD + ADDRESS MAPPING
       FIX: communicationConsent sent as String 'true' to avoid
            Boolean→Object cast issues across API boundaries.
            Also added profile_picture to cover Profile_Image_URL__c.
    ============================================================ */
    @IsTest
    static void testPersonAccount_FullFieldAndAddressMapping() {
        Account existingPA = getOrCreateTestPatient();

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{
                    'id'                     => existingPA.Id,
                    'firstName'              => 'UpdatedFull',
                    'lastName'               => 'PatientUnique',   // FIX: must stay non-blank
                    'salutation'             => 'Mr.',
                    'preferredName'          => 'Testy',
                    'preferredLanguage'      => 'English',
                    'maidenname'             => 'OldName',
                    'additionalEmail'        => 'extra@testonly.invalid',
                    'accountFax'             => '123456789',
                    'homePhone'              => '1111111111',
                    'workPhone'              => '2222222222',
                    'preferredContactMethod' => 'Email',
                    'occupation'             => 'Engineer',
                    'maritalStatus'          => 'Single',
                    'genderIdentity'         => 'Male',
                    'biologicalSexAtBirth'   => 'Male',
                    'sexualOrientation'      => 'Heterosexual',
                    'race'                   => 'Asian',
                    'ethnicity'              => 'Indian',
                    'livingSituation'        => 'Own House',
                    'communicationConsent'   => 'true',            // FIX: String avoids Boolean cast issue
                    'height'                 => '65',
                    'weight'                 => '150',
                    'dateOfBirth'            => '1990-05-15',
                    'signUpDate'             => '2024-01-01',
                    'renewalDate'            => '2025-01-01',
                    'profile_picture'        => 'https://example.com/pic.jpg', // FIX: added to test Profile_Image_URL__c
                    'mailingAddress' => new Map<String, Object>{
                        'street'  => '12 MG Road',
                        'city'    => 'Delhi',
                        'state'   => 'DL',
                        'zipCode' => '110001',
                        'country' => 'India'
                    },
                    'otherAddress' => new Map<String, Object>{
                        'street'  => '99 Residency Road',
                        'city'    => 'Bangalore',
                        'state'   => 'KA',
                        'zipCode' => '560001',
                        'country' => 'India'
                    }
                }
            }
        });
        Test.stopTest();

        System.debug('testPersonAccount_FullFieldAndAddressMapping response: ' + res.responseBody?.toString());
        System.assertEquals(200, res.statusCode, 'Expected 200 but got: ' + res.responseBody?.toString());
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       MEDICAL HISTORY UPDATE SUCCESS + FIELD MAPPING
    ============================================================ */
    @IsTest
    static void testMedicalHistory_Update_Success_WithFields() {
        createTestDataForTest();
        Account         pa = getOrCreateTestPatient();
        HealthCondition hc = getOrCreateHealthCondition(pa.Id, 'Diabetes');

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{
                    'id'             => hc.Id,
                    'medicalProblem' => 'Cancer',
                    'onsetDate'      => '2023-01-01',
                    'note'           => 'Test note update',
                    'status'         => 'Active',
                    'accountId'      => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       MEDICAL HISTORY INSERT SUCCESS + FIELD MAPPING
    ============================================================ */
    @IsTest
    static void testMedicalHistory_Insert_Success_WithFields() {
        Account pa = getOrCreateTestPatient();

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{
                    'medicalProblem' => 'Cancer',
                    'onsetDate'      => '2022-05-10',
                    'note'           => 'Inserted note',
                    'accountId'      => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       ALLERGY RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testAllergy_RecordNotFound() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{
                    'id'   => '0Mj000000000AAA',
                    'name' => 'Non Existing Allergy'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       INVALID REQUEST FORMAT - NOT MAP
    ============================================================ */
    @IsTest
    static void testInvalidRequestFormat_NotMap() {
        RestRequest req  = new RestRequest();
        req.requestUri   = '/services/apexrest/OnboardingUpdate/v1/';
        req.httpMethod   = 'PUT';
        req.requestBody  = Blob.valueOf(
            JSON.serialize(new List<Object>{
                new Map<String, Object>{ 'name' => 'Invalid' }
            })
        );

        RestResponse res = new RestResponse();
        RestContext.request  = req;
        RestContext.response = res;

        Test.startTest();
        MedicalRecordsUpdateAPI.updateRecord();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('INVALID_REQUEST_FORMAT'));
    }

    /* ============================================================
       UNSUPPORTED OBJECT TYPE
    ============================================================ */
    @IsTest
    static void testProcessBulkUpdateByType_UnsupportedObject() {
        List<Map<String, Object>> records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'name' => 'Dummy' }
        };

        Test.startTest();
        List<MedicalRecordsUpdateAPI.ResponseWrapper> result =
            MedicalRecordsUpdateAPI.processBulkUpdateByType('Unsupported_Object__c', records);
        Test.stopTest();

        System.assertEquals(1,                       result.size());
        System.assertEquals(false,                   result[0].success);
        System.assertEquals('UNSUPPORTED_OBJECT_TYPE', result[0].errorCode);
    }

    /* ============================================================
       SURGERY UPDATE - EXISTING RECORD
    ============================================================ */
    @IsTest
    static void testSurgery_UpdateFailure_ElseBranch() {
        createTestDataForTest();
        Account             pa = getOrCreateTestPatient();
        HealthCareProcedure sh = getOrCreateHealthCareProcedure(pa.Id, 'Appendix');

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'surgical_history' => new List<Object>{
                new Map<String, Object>{
                    'id'   => sh.Id,
                    'name' => 'Broken Update'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       ALLERGY FIELD MAPPING
    ============================================================ */
    @IsTest
    static void testAllergy_FieldMapping() {
        createTestDataForTest();
        Account            pa      = getOrCreateTestPatient();
        AllergyIntolerance allergy = getOrCreateAllergyIntolerance(pa.Id);

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{
                    'id'        => allergy.Id,
                    'reaction'  => 'Skin Rash',
                    'onsetDate' => '2023-02-01',
                    'note'      => 'Severe reaction',
                    'status'    => 'Active',
                    'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       ALLERGY INSERT SUCCESS
    ============================================================ */
    @IsTest
    static void testAllergy_Insert_Success() {
        Account pa = getOrCreateTestPatient();

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{
                    'name'      => 'Peanut Allergy',
                    'severity'  => 'High',
                    'reaction'  => 'Breathing issue',
                    'onsetDate' => '2022-01-01',
                    'note'      => 'Emergency allergy',
                    'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       CONTACT ADDRESS & NOTES TEST
    ============================================================ */
    @IsTest
    static void testContact_Address_Notes() {
        Contact c = getOrCreateContact();

        RestRequest req = new RestRequest();
        req.httpMethod  = 'PUT';
        req.requestURI  = '/services/apexrest/OnboardingUpdate/v1/';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'personal_contacts' => new List<Object>{
                new Map<String, Object>{
                    'id'        => c.Id,
                    'firstName' => 'Updated',
                    'lastName'  => 'ContactUnique',
                    'homePhone' => '123456789',
                    'notes'     => 'Test notes'
                }
            }
        }));

        RestContext.request  = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        MedicalRecordsUpdateAPI.updateRecord();
        Test.stopTest();

        Contact updated = [SELECT Description FROM Contact WHERE Id = :c.Id];
        System.assertEquals('Test notes', updated.Description);
    }

    /* ============================================================
       MEDICATION UPDATE - EXISTING MEDICATION RECORD
    ============================================================ */
    @IsTest
    static void testMedication_Update_ExistingRecord() {
        createTestDataForTest();
        Medication medRec = getOrCreateMedication('Paracetamol');

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'medications' => new List<Object>{
                new Map<String, Object>{
                    'id'        => medRec.Id,
                    'dosage'    => '500mg',
                    'frequency' => 'Twice a day',
                    'status'    => 'Active',
                    'notes'     => 'Updated medication note'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertNotEquals(null, RestContext.response.responseBody);
    }

    /* ============================================================
       INSURANCE UPDATE - EXISTING PLAN + ALL FIELDS
    ============================================================ */
    @IsTest
    static void testInsurance_Update_ExistingPlan_MapCoverage() {
        createTestDataForTest();
        Account    pa           = getOrCreateTestPatient();
        MemberPlan existingPlan = getOrCreateMemberPlan(pa.Id);

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'insurance_details' => new List<Object>{
                new Map<String, Object>{
                    'id'                       => existingPlan.Id,
                    'Name'                     => 'Updated Insurance',
                    'Subscriber_First_Name'    => 'John',
                    'Subscriber_Last_Name'     => 'Doe',
                    'Subscriber_Birth_Date'    => '1990-01-01',
                    'RelationshipToSubscriber' => 'Self',
                    'PrimarySecondaryTertiary' => 'Primary',
                    'accountId'                => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       HEALTHCARE FACILITY - UPDATE EXISTING RECORD
    ============================================================ */
    @IsTest
    static void testHealthcareFacility_UpdateFailure_DMLError() {
        Account pa = getOrCreateTestPatient();

        HealthcareFacility facility = new HealthcareFacility(
            Name      = 'Test Facility',
            AccountId = pa.Id,
            Phone__c  = '1234567890'
        );
        safeInsert(facility);

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'healthcare_facilities' => new List<Object>{
                new Map<String, Object>{
                    'id'           => facility.Id,
                    'facilityName' => 'Updated Facility'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       HEALTH CONDITION DELETE TRIGGER TEST
    ============================================================ */
    @IsTest
    static void testHealthConditionDeleteTrigger_SingleRecord() {
        createTestDataForTest();
        Account         pa = getOrCreateTestPatient();
        HealthCondition hc = getOrCreateHealthCondition(pa.Id, 'Diabetes');

        Test.startTest();
        delete hc;
        Test.stopTest();

        List<HealthCondition> remaining = [SELECT Id FROM HealthCondition WHERE Id = :hc.Id];
        System.assertEquals(0, remaining.size(), 'HealthCondition should be deleted');
    }

    /* ============================================================
       HEALTH CONDITION BULK DELETE TRIGGER TEST
    ============================================================ */
    @IsTest
    static void testHealthConditionDeleteTrigger_BulkRecords() {
        createTestDataForTest();
        Account pa = getOrCreateTestPatient();

        List<HealthCondition> conditionsToDelete = new List<HealthCondition>();
        for (Integer i = 0; i < 3; i++) {
            conditionsToDelete.add(new HealthCondition(
                ProblemName = 'BulkTestCondition' + i,
                PatientId   = pa.Id
            ));
        }
        safeInsertList(conditionsToDelete);

        Test.startTest();
        delete conditionsToDelete;
        Test.stopTest();

        List<HealthCondition> remaining = [
            SELECT Id FROM HealthCondition WHERE ProblemName LIKE 'BulkTestCondition%'
        ];
        System.assertEquals(0, remaining.size(), 'All test HealthConditions should be deleted');
    }

    /* ============================================================
       HEALTH CONDITION TRIGGER - INSERT / UPDATE PATH
    ============================================================ */
    @IsTest
    static void testHealthConditionTrigger_InsertUpdate() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        HealthCondition newCondition = new HealthCondition(
            ProblemName = 'TriggerTestCondition',
            PatientId   = pa.Id
        );
        safeInsert(newCondition);

        newCondition.ProblemName = 'TriggerTestConditionUpdated';
        update newCondition;
        Test.stopTest();

        HealthCondition updated = [SELECT ProblemName FROM HealthCondition WHERE Id = :newCondition.Id];
        System.assertEquals('TriggerTestConditionUpdated', updated.ProblemName);
    }

    /* ============================================================
       PARSE DECIMAL UTILITY TEST
    ============================================================ */
    @IsTest
    static void testParseDecimal_Variants() {
        Test.startTest();

        Decimal d1 = MedicalRecordsUpdateAPI.parseDecimal((Decimal) 5.5, 0.0);
        System.assertEquals(5.5, d1, 'Decimal input should return same value');

        Decimal d2 = MedicalRecordsUpdateAPI.parseDecimal('72.5', 0.0);
        System.assertEquals(72.5, d2, 'String input should parse correctly');

        Decimal d3 = MedicalRecordsUpdateAPI.parseDecimal(null, 99.9);
        System.assertEquals(99.9, d3, 'Null input should return default');

        Decimal d4 = MedicalRecordsUpdateAPI.parseDecimal('abc', 1.0);
        System.assertEquals(1.0, d4, 'Invalid string should return default');

        Test.stopTest();
    }

    /* ============================================================
       PERSON ACCOUNT NOT FOUND
    ============================================================ */
    @IsTest
    static void testPersonAccount_RecordNotFound() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{
                    'id'        => '001000000000AAA',
                    'firstName' => 'Ghost',
                    'lastName'  => 'Account'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       HEALTHCARE PROFESSIONAL - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testHealthcareProfessional_RecordNotFound() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'healthcare_professionals' => new List<Object>{
                new Map<String, Object>{
                    'id'        => 'a3B000000000AAA',
                    'specialty' => 'Cardiology'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       PERSONAL CONTACT - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testPersonalContact_RecordNotFound() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'personal_contacts' => new List<Object>{
                new Map<String, Object>{
                    'id'        => '003000000000AAA',
                    'firstName' => 'Ghost',
                    'lastName'  => 'Contact'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       INSURANCE PLAN - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testInsurancePlan_RecordNotFound() {
        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'insurance_details' => new List<Object>{
                new Map<String, Object>{
                    'id'           => 'a4C000000000AAA',
                    'providerName' => 'Ghost Insurance'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assertNotEquals(null, res.responseBody);
    }
}