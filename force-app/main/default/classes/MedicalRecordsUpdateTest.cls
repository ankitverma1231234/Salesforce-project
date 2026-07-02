@isTest(SeeAllData=true)
public class MedicalRecordsUpdateTest {

    private class MockFileDownload implements HttpCalloutMock {
        private Integer statusCode;
        private Blob    body;

        public MockFileDownload(Integer statusCode, Blob body) {
            this.statusCode = statusCode;
            this.body       = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            if (body != null) res.setBodyAsBlob(body);
            return res;
        }
    }

    private static void safeInsert(SObject record) {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        Database.SaveResult sr = Database.insert(record, dml);
        if (!sr.isSuccess()) {
            throw new DmlException('safeInsert failed: ' + sr.getErrors()[0].getMessage());
        }
    }

    private static void safeInsertList(List<SObject> records) {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        List<Database.SaveResult> results = Database.insert(records, dml);
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                throw new DmlException('safeInsertList failed: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    /* ============================================================
       HELPER METHODS - GET OR CREATE TEST DATA
    ============================================================ */
    private static Account getOrCreateTestPatient() {
        String testEmail = 'medtest.patient.unique@testonly.invalid';
        List<Account> existing = [
            SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone
            FROM Account
            WHERE PersonEmail = :testEmail AND IsPersonAccount = true
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

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
        List<Contact> existing = [SELECT Id, Email FROM Contact WHERE Email = :testEmail LIMIT 1];
        if (!existing.isEmpty()) return existing[0];

        Contact c = new Contact(FirstName = 'Emergency', LastName = 'ContactUnique', Email = testEmail);
        safeInsert(c);
        return c;
    }

    private static HealthCondition getOrCreateHealthCondition(Id patientId, String problemName) {
        List<HealthCondition> existing = [
            SELECT Id FROM HealthCondition
            WHERE ProblemName = :problemName AND PatientId = :patientId LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        HealthCondition hc = new HealthCondition(ProblemName = problemName, PatientId = patientId);
        safeInsert(hc);
        return hc;
    }

    private static HealthCareProcedure getOrCreateHealthCareProcedure(Id patientId, String name) {
        List<HealthCareProcedure> existing = [
            SELECT Id FROM HealthCareProcedure
            WHERE Name = :name AND Patient__c = :patientId LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        HealthCareProcedure procedure = new HealthCareProcedure(Name = name, Patient__c = patientId);
        safeInsert(procedure);
        return procedure;
    }

    private static AllergyIntolerance getOrCreateAllergyIntolerance(Id patientId) {
        List<AllergyIntolerance> existing = [
            SELECT Id FROM AllergyIntolerance WHERE PatientId = :patientId LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        AllergyIntolerance allergy = new AllergyIntolerance(PatientId = patientId);
        safeInsert(allergy);
        return allergy;
    }

    private static Medication getOrCreateMedication(String name) {
        List<Medication> existing = [SELECT Id FROM Medication WHERE Name = :name LIMIT 1];
        if (!existing.isEmpty()) return existing[0];

        Medication med = new Medication(Name = name);
        safeInsert(med);
        return med;
    }

    private static MemberPlan getOrCreateMemberPlan(Id memberId) {
        List<MemberPlan> existing = [SELECT Id FROM MemberPlan WHERE MemberId = :memberId LIMIT 1];
        if (!existing.isEmpty()) return existing[0];

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

    private static Id getAnyVaccineCodeId() {
        List<CodeSetBundle> namedCodes = [
            SELECT Id
            FROM CodeSetBundle
            WHERE Name = 'Test Vaccine'
            LIMIT 1
        ];
        if (!namedCodes.isEmpty()) return namedCodes[0].Id;

        List<CodeSetBundle> anyCodes = [SELECT Id FROM CodeSetBundle LIMIT 1];
        return anyCodes.isEmpty() ? null : anyCodes[0].Id;
    }

    private static PatientImmunization getOrCreatePatientImmunization(Id patientId) {
        Id vaccineCodeId = getAnyVaccineCodeId();
        System.assertNotEquals(null, vaccineCodeId, 'A CodeSetBundle record is required for PatientImmunization tests.');

        PatientImmunization vaccination = new PatientImmunization(
            PatientId       = patientId,
            Status          = 'Completed',
            VaccineCodeId   = vaccineCodeId,
            VaccinationDate = System.now()
        );
        vaccination.put('Vaccine_Name__c', 'Existing Test Vaccine');
        safeInsert(vaccination);
        return vaccination;
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
       MAIN SUCCESS FLOW - ALL MAJOR GROUPS
    ============================================================ */
    @IsTest
    static void testUpdateRecord_SuccessFlow_AllGroups() {
        createTestDataForTest();
        Account             pa      = getOrCreateTestPatient();
        AllergyIntolerance  allergy = getOrCreateAllergyIntolerance(pa.Id);
        HealthCondition     mh      = getOrCreateHealthCondition(pa.Id, 'Diabetes');
        HealthCareProcedure sh      = getOrCreateHealthCareProcedure(pa.Id, 'Appendix');

        Test.setMock(HttpCalloutMock.class, new MockFileDownload(200, Blob.valueOf('PDF_CONTENT')));

        RestResponse res;
        Test.startTest();
        res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{ 'id' => allergy.Id, 'name' => 'Dust Allergy', 'severity' => 'High', 'accountId' => pa.Id }
            },
            'medical_history' => new List<Object>{
                new Map<String, Object>{ 'id' => mh.Id, 'medicalProblem' => 'Type 2 Diabetes', 'accountId' => pa.Id }
            },
            'surgical_history' => new List<Object>{
                new Map<String, Object>{ 'id' => sh.Id, 'name' => 'Appendix Surgery', 'accountId' => pa.Id }
            },
            'basic_details' => new List<Object>{
                new Map<String, Object>{ 'id' => pa.Id, 'firstName' => 'UpdatedMed', 'lastName' => 'PatientUnique' }
            },
            'medications' => new List<Object>{
                new Map<String, Object>{
                    'dosage' => '10mg', 'frequency' => 'Once a day', 'notes' => 'Test medication',
                    'status' => 'Active', 'accountId' => pa.Id, 'medication' => 'TestMedDrug'
                }
            },
            'insurance_details' => new List<Object>{
                new Map<String, Object>{
                    'providerName' => 'Blue Cross', 'memberNumber' => 'MEM123', 'GroupNumber' => 'GRP456',
                    'RelationshipToSubscriber' => 'Self', 'PrimarySecondaryTertiary' => 'Primary', 'accountId' => pa.Id
                }
            },
            'healthcare_professionals' => new List<Object>{
                new Map<String, Object>{
                    'professionalName' => 'Dr. John Smith', 'specialty' => 'Cardiology',
                    'phoneNumber' => '9999999999', 'email' => 'doc@testonly.invalid', 'accountId' => pa.Id
                }
            },
            'healthcare_facilities' => new List<Object>{
                new Map<String, Object>{
                    'facilityName' => 'Apollo Hospital', 'phoneNumber' => '8888888888',
                    'email' => 'facility@testonly.invalid', 'accountId' => pa.Id,
                    'address' => new Map<String, Object>{ 'street' => 'MG Road', 'city' => 'Delhi', 'state' => 'DL', 'zipCode' => '110001' }
                }
            },
            'personal_contacts' => new List<Object>{
                new Map<String, Object>{
                    'firstName' => 'John', 'lastName' => 'DoeTest', 'email' => 'john.doe.test@testonly.invalid',
                    'relationship' => 'Brother', 'mobilePhone' => '7777777777',
                    'emergencyContact' => true, 'authorizedToDisclose' => true, 'healthcareSurrogate' => false,
                    'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody);
        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       DOCUMENT - INSERT NEW FILE (HTTP 200 mock — file downloads OK)
    ============================================================ */
    @IsTest
    static void testDocument_Insert_Success() {
        Account pa = getOrCreateTestPatient();

        // Mock the S3/URL download so FileUpsertHelper.downloadFile returns a blob
        Test.setMock(HttpCalloutMock.class, new MockFileDownload(200, Blob.valueOf('FAKE_PDF_BYTES')));

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'document' => new List<Object>{
                new Map<String, Object>{
                    'title'         => 'Test Document',
                    'file_name'     => 'test.pdf',
                    'document_url'  => 'https://baton-care.s3.us-east-1.amazonaws.com/test.pdf',
                    'Accountid'     => pa.Id,
                    'description'   => 'Test description',
                    'document_type' => 'Radiology',
                    'source_type'   => 'Metriport',
                    'created_date'  => '2026-06-18T00:00:00.000Z',
                    'is_deleted'    => false
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('File created') || body.contains('success'),
            'Expected file created response but got: ' + body);
    }

    @IsTest
    static void testDocument_Update_ExistingCheckbox() {
        Account pa = getOrCreateTestPatient();

        // Create a real ContentVersion first
        ContentVersion cv = new ContentVersion(
            Title                  = 'Existing File',
            PathOnClient           = 'existing.pdf',
            VersionData            = Blob.valueOf('existing content'),
            FirstPublishLocationId = pa.Id,
            IsMajorVersion         = true
        );
        insert cv;

        // No HTTP mock needed — update path doesn't download a file
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'document' => new List<Object>{
                new Map<String, Object>{
                    'id'         => cv.Id,
                    'is_deleted' => true   // triggers Send_File_to_Portal__c = false
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('Checkbox updated'),
            'Expected checkbox update response but got: ' + body);

        ContentVersion updated = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(false, updated.Send_File_to_Portal__c);
    }

    /* ============================================================
       DOCUMENT - DOWNLOAD FAILURE (HTTP non-200 response)
       FileUpsertHelper returns 'File download failed'
    ============================================================ */
    @IsTest
    static void testDocument_Insert_DownloadFailure() {
        Account pa = getOrCreateTestPatient();

        // Mock returns 500 → downloadFile returns null → graceful failure
        Test.setMock(HttpCalloutMock.class, new MockFileDownload(500, null));

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'document' => new List<Object>{
                new Map<String, Object>{
                    'title'        => 'Bad File',
                    'file_name'    => 'bad.pdf',
                    'document_url' => 'https://baton-care.s3.us-east-1.amazonaws.com/bad.pdf',
                    'Accountid'    => pa.Id,
                    'is_deleted'   => false
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('File download failed'),
            'Expected download failure message but got: ' + body);
    }

    /* ============================================================
       DOCUMENT - MISSING document_url OR file_name
       FileUpsertHelper returns 'Missing document_url or file_name'
    ============================================================ */
    @IsTest
    static void testDocument_Insert_MissingUrlAndFileName() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'document' => new List<Object>{
                new Map<String, Object>{
                    'title'     => 'No URL File',
                    'Accountid' => pa.Id
                    // document_url and file_name intentionally omitted
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('Missing document_url or file_name'),
            'Expected missing field message but got: ' + body);
    }

    /* ============================================================
       DOCUMENT - is_deleted as String 'true' (covers string branch
       in FileUpsertHelper deleteFlag parsing)
    ============================================================ */
    @IsTest
    static void testDocument_IsDeleted_StringTrue() {
        Account pa = getOrCreateTestPatient();

        ContentVersion cv = new ContentVersion(
            Title                  = 'String Delete Test',
            PathOnClient           = 'strdelete.pdf',
            VersionData            = Blob.valueOf('content'),
            FirstPublishLocationId = pa.Id,
            IsMajorVersion         = true
        );
        insert cv;

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'document' => new List<Object>{
                new Map<String, Object>{
                    'id'         => cv.Id,
                    'is_deleted' => 'true'   // String instead of Boolean
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        ContentVersion updated = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(false, updated.Send_File_to_Portal__c);
    }

    /* ============================================================
       NORMALIZE OBJECT TYPE - ALTERNATE ALIASES
    ============================================================ */
    @IsTest
    static void testNormalizeObjectType_AlternateAliases() {
        Account pa = getOrCreateTestPatient();

        Test.setMock(HttpCalloutMock.class, new MockFileDownload(200, Blob.valueOf('FAKE_BYTES')));

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'allergy' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Pollen', 'severity' => 'Low', 'accountId' => pa.Id }
            },
            'medication' => new List<Object>{
                new Map<String, Object>{ 'medication' => 'Aspirin', 'dosage' => '100mg', 'accountId' => pa.Id }
            },
            'medicalhistory' => new List<Object>{
                new Map<String, Object>{ 'medicalProblem' => 'Flu', 'accountId' => pa.Id }
            },
            'surgicalhistory' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Tonsillectomy', 'accountId' => pa.Id }
            },
            'basicdetails' => new List<Object>{
                new Map<String, Object>{ 'id' => pa.Id, 'firstName' => 'AliasTest', 'lastName' => 'PatientUnique' }
            },
            'insurancedetails' => new List<Object>{
                new Map<String, Object>{ 'providerName' => 'Alias Insurance', 'accountId' => pa.Id }
            },
            'personalcontacts' => new List<Object>{
                new Map<String, Object>{ 'firstName' => 'AliasContact', 'lastName' => 'Test', 'accountId' => pa.Id }
            },
            'healthcarefacilities' => new List<Object>{
                new Map<String, Object>{ 'facilityName' => 'Alias Hospital', 'accountId' => pa.Id }
            },
            'healthcareprofessionals' => new List<Object>{
                new Map<String, Object>{ 'professionalName' => 'Dr Alias', 'accountId' => pa.Id }
            }
        });
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody);
        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       NORMALIZE OBJECT TYPE - 'document' alias with correct payload
    ============================================================ */
    @IsTest
    static void testNormalizeObjectType_DocumentAlias() {
        Account pa = getOrCreateTestPatient();

        // Mock download so FileUpsertHelper doesn't fail on HTTP
        Test.setMock(HttpCalloutMock.class, new MockFileDownload(200, Blob.valueOf('PDF')));

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'document' => new List<Object>{
                new Map<String, Object>{
                    'title'        => 'AliasDoc',
                    'file_name'    => 'aliasdoc.pdf',
                    'document_url' => 'https://baton-care.s3.us-east-1.amazonaws.com/aliasdoc.pdf',
                    'Accountid'    => pa.Id,
                    'is_deleted'   => false
                }
            }
        });
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody);
        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       INVALID GROUP NAME TEST
    ============================================================ */
    @IsTest
    static void testUpdateRecord_InvalidGroup() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'unknown_group' => new List<Object>{ new Map<String, Object>{ 'name' => 'Invalid' } }
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
       INVALID REQUEST FORMAT - NOT MAP
    ============================================================ */
    @IsTest
    static void testInvalidRequestFormat_NotMap() {
        RestRequest req  = new RestRequest();
        req.requestUri   = '/services/apexrest/OnboardingUpdate/v1/';
        req.httpMethod   = 'PUT';
        req.requestBody  = Blob.valueOf(JSON.serialize(
            new List<Object>{ new Map<String, Object>{ 'name' => 'Invalid' } }
        ));
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
       TOTAL RECORD LIMIT EXCEEDED (> 1000)
    ============================================================ */
    @IsTest
    static void testTotalRecordLimitExceeded() {
        Account pa = getOrCreateTestPatient();
        List<Object> bigList = new List<Object>();
        for (Integer i = 0; i < 600; i++) {
            bigList.add(new Map<String, Object>{ 'medicalProblem' => 'Condition' + i, 'accountId' => pa.Id });
        }
        List<Object> bigList2 = new List<Object>();
        for (Integer i = 0; i < 500; i++) {
            bigList2.add(new Map<String, Object>{ 'name' => 'Allergy' + i, 'accountId' => pa.Id });
        }

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medical_history' => bigList,
            'allergies'       => bigList2
        });
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('RECORD_LIMIT_EXCEEDED'));
    }

    /* ============================================================
       PER-OBJECT-TYPE RECORD LIMIT EXCEEDED (> 500)
    ============================================================ */
    @IsTest
    static void testObjectTypeLimitExceeded() {
        Account pa = getOrCreateTestPatient();
        List<Object> bigList = new List<Object>();
        for (Integer i = 0; i < 501; i++) {
            bigList.add(new Map<String, Object>{ 'medicalProblem' => 'Condition' + i, 'accountId' => pa.Id });
        }

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{ 'medical_history' => bigList });
        Test.stopTest();

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

        System.assertEquals(1,                         result.size());
        System.assertEquals(false,                     result[0].success);
        System.assertEquals('UNSUPPORTED_OBJECT_TYPE', result[0].errorCode);
    }

    /* ============================================================
       IMMUNIZATION - INSERT SUCCESS VIA SINGULAR ALIAS
    ============================================================ */
    @IsTest
    static void testImmunization_Insert_Success() {
        Account pa = getOrCreateTestPatient();
        Id vaccineCodeId = getAnyVaccineCodeId();
        System.assertNotEquals(null, vaccineCodeId, 'A CodeSetBundle record is required for PatientImmunization tests.');

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'immunization' => new List<Object>{
                new Map<String, Object>{
                    'vaccine_name'     => 'COVID Booster ' + System.currentTimeMillis(),
                    'status'           => 'Completed',
                    'vaccination_date' => '2024-04-05T10:30:00Z',
                    'accountId'        => pa.Id,
                    'vaccineCodeId'    => vaccineCodeId
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('"successCount":1'), body);
        System.assert(body.contains('COVID Booster'), body);
    }

    /* ============================================================
       IMMUNIZATION - INSERT USING DEFAULT VACCINE CODE LOOKUP
    ============================================================ */
    @IsTest
    static void testImmunization_Insert_DefaultVaccineCodeLookup() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'immunizations' => new List<Object>{
                new Map<String, Object>{
                    'vaccine_name'     => 'Default Vaccine Lookup ' + System.currentTimeMillis(),
                    'status'           => 'Completed',
                    'vaccination_date' => '2024-04-06',
                    'accountId'        => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('Default Vaccine Lookup'), body);
    }

    /* ============================================================
       IMMUNIZATION - UPDATE SUCCESS WITH ACCOUNT CONTACT MAPPING
    ============================================================ */
    @IsTest
    static void testImmunization_Update_Success() {
        Account pa = getOrCreateTestPatient();
        PatientImmunization vaccination = getOrCreatePatientImmunization(pa.Id);

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'immunizations' => new List<Object>{
                new Map<String, Object>{
                    'id'               => vaccination.Id,
                    'vaccine_name'     => 'Updated Vaccine ' + System.currentTimeMillis(),
                    'status'           => 'Completed',
                    'vaccination_date' => '2024-05-06'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('"successCount":1'), body);
        System.assert(body.contains('Updated Vaccine'), body);
    }

    /* ============================================================
       IMMUNIZATION - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testImmunization_RecordNotFound() {
        Account pa = getOrCreateTestPatient();
        PatientImmunization vaccination = getOrCreatePatientImmunization(pa.Id);
        Id missingId = vaccination.Id;
        delete vaccination;

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'immunizations' => new List<Object>{
                new Map<String, Object>{
                    'id'               => missingId,
                    'vaccine_name'     => 'Missing Vaccine',
                    'status'           => 'Completed',
                    'vaccination_date' => '2024-05-07',
                    'accountId'        => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('"failureCount":1'), body);
        System.assert(body.contains('Missing Vaccine'), body);
    }

    /* ============================================================
       IMMUNIZATION - INSERT DML FAILURE
    ============================================================ */
    @IsTest
    static void testImmunization_Insert_DmlFailure() {
        Id vaccineCodeId = getAnyVaccineCodeId();
        System.assertNotEquals(null, vaccineCodeId, 'A CodeSetBundle record is required for PatientImmunization tests.');

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'immunizations' => new List<Object>{
                new Map<String, Object>{
                    'vaccine_name'     => 'Missing Patient Vaccine',
                    'status'           => 'Completed',
                    'vaccination_date' => '2024-05-08',
                    'vaccineCodeId'    => vaccineCodeId
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('"failureCount":1'), body);
        System.assert(body.contains('Missing Patient Vaccine'), body);
    }

    /* ============================================================
       IMMUNIZATION - UPDATE DML FAILURE
    ============================================================ */
    @IsTest
    static void testImmunization_Update_DmlFailure() {
        Account pa = getOrCreateTestPatient();
        Contact c = getOrCreateContact();
        PatientImmunization vaccination = getOrCreatePatientImmunization(pa.Id);

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'immunizations' => new List<Object>{
                new Map<String, Object>{
                    'id'               => vaccination.Id,
                    'vaccine_name'     => 'Wrong Patient Reference',
                    'status'           => 'Completed',
                    'vaccination_date' => '2024-05-09',
                    'vaccineCodeId'    => c.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('"failureCount":1'), body);
        System.assert(body.contains('Wrong Patient Reference'), body);
    }

    /* ============================================================
       IMMUNIZATION - EMPTY INPUT ROUTING
    ============================================================ */
    @IsTest
    static void testImmunization_EmptyInputRouting() {
        Test.startTest();
        List<MedicalRecordsUpdateAPI.ResponseWrapper> emptyResult =
            MedicalRecordsUpdateAPI.processBulkUpdateByType(
                'PatientImmunization',
                new List<Map<String, Object>>()
            );
        List<MedicalRecordsUpdateAPI.ResponseWrapper> nullResult =
            MedicalRecordsUpdateAPI.processBulkUpdateByType('PatientImmunization', null);
        Test.stopTest();

        System.assertEquals(0, emptyResult.size());
        System.assertEquals(0, nullResult.size());
    }

    /* ============================================================
       SURGICAL HISTORY - INSERT (no ID)
    ============================================================ */
    @IsTest
    static void testSurgicalHistory_InsertPath_NoId() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'surgical_history' => new List<Object>{
                new Map<String, Object>{
                    'name' => 'Knee Replacement-' + System.currentTimeMillis(),
                    'surgeryDate' => '2024-01-10', 'note' => 'Inserted via test', 'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       SURGICAL HISTORY - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testSurgicalHistory_RecordNotFound() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'surgical_history' => new List<Object>{
                new Map<String, Object>{ 'id' => '0JQ000000000AAA', 'name' => 'Missing Surgery' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       SURGICAL HISTORY - UPDATE SUCCESS
    ============================================================ */
    @IsTest
    static void testSurgicalHistory_UpdateSuccess() {
        createTestDataForTest();
        Account             pa = getOrCreateTestPatient();
        HealthCareProcedure sh = getOrCreateHealthCareProcedure(pa.Id, 'Appendix');

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'surgical_history' => new List<Object>{
                new Map<String, Object>{ 'id' => sh.Id, 'name' => 'Updated Appendix', 'surgeryDate' => '2023-06-15', 'note' => 'Updated note' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MEDICAL HISTORY - UPDATE SUCCESS + ALL FIELDS
    ============================================================ */
    @IsTest
    static void testMedicalHistory_Update_Success_WithFields() {
        createTestDataForTest();
        Account         pa = getOrCreateTestPatient();
        HealthCondition hc = getOrCreateHealthCondition(pa.Id, 'Diabetes');

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{
                    'id' => hc.Id, 'medicalProblem' => 'Cancer', 'onsetDate' => '2023-01-01',
                    'note' => 'Test note update', 'status' => 'Active', 'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MEDICAL HISTORY - INSERT SUCCESS
    ============================================================ */
    @IsTest
    static void testMedicalHistory_Insert_Success() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{
                    'medicalProblem' => 'Cancer', 'onsetDate' => '2022-05-10',
                    'note' => 'Inserted note', 'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MEDICAL HISTORY - INSERT FAILURE (missing required field)
    ============================================================ */
    @IsTest
    static void testMedicalHistory_InsertFailure_MissingPatient() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{ 'medicalProblem' => 'Failure Case' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MEDICAL HISTORY - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testMedicalHistory_RecordNotFound() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{ 'id' => '0QL000000000AAA', 'medicalProblem' => 'Test' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       ALLERGY - FIELD MAPPING (update)
    ============================================================ */
    @IsTest
    static void testAllergy_FieldMapping_Update() {
        createTestDataForTest();
        Account            pa      = getOrCreateTestPatient();
        AllergyIntolerance allergy = getOrCreateAllergyIntolerance(pa.Id);

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{
                    'id' => allergy.Id, 'name' => 'Updated Allergy', 'severity' => 'Moderate',
                    'reaction' => 'Skin Rash', 'onsetDate' => '2023-02-01',
                    'note' => 'Severe reaction', 'status' => 'Active', 'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       ALLERGY - INSERT SUCCESS
    ============================================================ */
    @IsTest
    static void testAllergy_Insert_Success() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{
                    'name' => 'Peanut Allergy', 'severity' => 'High', 'reaction' => 'Breathing issue',
                    'onsetDate' => '2022-01-01', 'note' => 'Emergency allergy', 'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       ALLERGY - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testAllergy_RecordNotFound() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{ 'id' => '0Mj000000000AAA', 'name' => 'Non Existing Allergy' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       ALLERGY - INSERT WITHOUT NAME
    ============================================================ */
    @IsTest
    static void testAllergy_Insert_NoName() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{ 'severity' => 'Low', 'reaction' => 'Sneezing', 'accountId' => pa.Id }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MEDICATION - FIND OR CREATE: cache hit path
    ============================================================ */
    @IsTest
    static void testFindOrCreateMedications_CacheHitPath() {
        Test.startTest();
        Set<String> names = new Set<String>{ 'CacheMedication' };
        Map<String, String> result1 = MedicalRecordsUpdateAPI.findOrCreateMedications(names);
        Map<String, String> result2 = MedicalRecordsUpdateAPI.findOrCreateMedications(names);
        Test.stopTest();

        System.assertNotEquals(null, result1);
        System.assertNotEquals(null, result2);
    }

    /* ============================================================
       MEDICATION - FIND OR CREATE: provided ID with rename
    ============================================================ */
    @IsTest
    static void testFindOrCreateMedications_ProvidedIdWithRename() {
        Medication med = getOrCreateMedication('OldMedName');

        Test.startTest();
        Set<String> names = new Set<String>{ 'NewMedName' };
        Map<String, String> nameToIdProvided = new Map<String, String>{ 'newmedname' => med.Id };
        Map<String, String> result = MedicalRecordsUpdateAPI.findOrCreateMedications(names, nameToIdProvided);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    /* ============================================================
       MEDICATION - FIND OR CREATE: provided ID not in DB
    ============================================================ */
    @IsTest
    static void testFindOrCreateMedications_ProvidedIdNotInDB() {
        Test.startTest();
        Set<String> names = new Set<String>{ 'GhostMedName' };
        Map<String, String> nameToIdProvided = new Map<String, String>{ 'ghostmedname' => '01t000000000AAAAAA' };
        Map<String, String> result = MedicalRecordsUpdateAPI.findOrCreateMedications(names, nameToIdProvided);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    /* ============================================================
       MEDICATION - FIND OR CREATE: fuzzy startsWith match
    ============================================================ */
    @IsTest
    static void testFindOrCreateMedications_FuzzyStartsWithMatch() {
        getOrCreateMedication('Amoxicillin 500mg');

        Test.startTest();
        Set<String> names = new Set<String>{ 'amoxicillin' };
        Map<String, String> result = MedicalRecordsUpdateAPI.findOrCreateMedications(names);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    /* ============================================================
       MEDICATION - FIND OR CREATE: empty input
    ============================================================ */
    @IsTest
    static void testFindOrCreateMedications_EmptyInput() {
        Test.startTest();
        Map<String, String> result = MedicalRecordsUpdateAPI.findOrCreateMedications(new Set<String>());
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }

    /* ============================================================
       MEDICATION - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testMedication_RecordNotFound() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medications' => new List<Object>{
                new Map<String, Object>{
                    'id' => '0RX000000000000AAA', 'dosage' => '20mg',
                    'frequency' => 'Twice a day', 'status' => 'Active', 'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MEDICATION - ALL FIELDS
    ============================================================ */
    @IsTest
    static void testMedication_Insert_AllFields() {
        Account pa      = getOrCreateTestPatient();
        Contact contact = getOrCreateContact();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medications' => new List<Object>{
                new Map<String, Object>{
                    'medication' => 'Ibuprofen', 'dosage' => '400mg',
                    'frequency'  => 'Three times a day', 'reason' => 'Pain relief',
                    'notes'      => 'Take after food', 'status' => 'Active',
                    'startDate'  => '2024-01-01 00:00:00', 'endDate' => '2024-06-01 00:00:00',
                    'contactId'  => contact.Id, 'accountId' => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MEDICATION - UPDATE EXISTING RECORD
    ============================================================ */
    @IsTest
    static void testMedication_Update_ExistingRecord() {
        createTestDataForTest();
        Account    pa     = getOrCreateTestPatient();
        Medication medRec = getOrCreateMedication('Paracetamol');

        MedicationStatement ms = new MedicationStatement(
            MedicationId = medRec.Id, PatientId = pa.Id, Status = 'Active'
        );
        safeInsert(ms);

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medications' => new List<Object>{
                new Map<String, Object>{
                    'id'         => ms.Id,
                    'medication' => 'Paracetamol',
                    'dosage'     => '500mg',
                    'frequency'  => 'Twice a day',
                    'status'     => 'Active',
                    'notes'      => 'Updated medication note'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
    }

    /* ============================================================
       INSURANCE - UPDATE EXISTING PLAN + ALL FIELDS
    ============================================================ */
    @IsTest
    static void testInsurance_Update_AllFields() {
        createTestDataForTest();
        Account    pa           = getOrCreateTestPatient();
        MemberPlan existingPlan = getOrCreateMemberPlan(pa.Id);

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'insurance_details' => new List<Object>{
                new Map<String, Object>{
                    'id'                       => existingPlan.Id,
                    'Name'                     => 'Updated Insurance Via Name Key',
                    'providerName'             => 'Blue Shield',
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
    }

    /* ============================================================
       INSURANCE - INSERT NEW PLAN
    ============================================================ */
    @IsTest
    static void testInsurance_Insert_NewPlan() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'insurance_details' => new List<Object>{
                new Map<String, Object>{
                    'providerName'             => 'New Insurer',
                    'memberNumber'             => 'NEW-MEM-001',
                    'GroupNumber'              => 'NEW-GRP-001',
                    'RelationshipToSubscriber' => 'Spouse',
                    'PrimarySecondaryTertiary' => 'Secondary',
                    'accountId'                => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       INSURANCE - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testInsurancePlan_RecordNotFound() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'insurance_details' => new List<Object>{
                new Map<String, Object>{ 'id' => 'a4C000000000AAA', 'providerName' => 'Ghost Insurance' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       HEALTHCARE FACILITY - INSERT WITH FULL STATE NAME
    ============================================================ */
    @IsTest
    static void testHealthcareFacility_Insert_FullStateName() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'healthcare_facilities' => new List<Object>{
                new Map<String, Object>{
                    'facilityName' => 'California Hospital', 'phoneNumber' => '8888888888',
                    'email'        => 'cafacility@testonly.invalid', 'accountId' => pa.Id,
                    'faxNumber'    => '1112223333', 'website' => 'https://cahospital.testonly.invalid',
                    'address'      => new Map<String, Object>{
                        'street' => '100 Sunset Blvd', 'city' => 'Los Angeles',
                        'state'  => 'California', 'zipCode' => '90001', 'country' => 'US'
                    }
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       HEALTHCARE FACILITY - UPDATE EXISTING RECORD
    ============================================================ */
    @IsTest
    static void testHealthcareFacility_UpdateExistingRecord() {
        Account pa = getOrCreateTestPatient();
        HealthcareFacility facility = new HealthcareFacility(
            Name = 'Test Facility', AccountId = pa.Id, Phone__c = '1234567890'
        );
        safeInsert(facility);

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'healthcare_facilities' => new List<Object>{
                new Map<String, Object>{
                    'id'           => facility.Id,
                    'facilityName' => 'Updated Facility',
                    'name'         => 'Updated Facility Name',
                    'faxNumber'    => '9998887777',
                    'website'      => 'https://updated.testonly.invalid'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       HEALTHCARE FACILITY - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testHealthcareFacility_RecordNotFound() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'healthcare_facilities' => new List<Object>{
                new Map<String, Object>{ 'id' => 'a2N000000000AAA', 'facilityType' => 'Hospital' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       HEALTHCARE PROFESSIONAL - INSERT WITH ADDRESS
    ============================================================ */
    @IsTest
    static void testHealthcareProfessional_Insert_WithAddress_FullStateName() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'healthcare_professionals' => new List<Object>{
                new Map<String, Object>{
                    'professionalName' => 'Dr Address Test', 'specialty' => 'General Medicine',
                    'phoneNumber'      => '9999999999', 'email' => 'address@testonly.invalid',
                    'faxNumber'        => '1234567890', 'website' => 'https://draddrtest.testonly.invalid',
                    'accountId'        => pa.Id,
                    'address'          => new Map<String, Object>{
                        'street' => '123 Test Street', 'city' => 'Mumbai',
                        'state'  => 'Maharashtra', 'zipCode' => '400001', 'country' => 'IN'
                    }
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       HEALTHCARE PROFESSIONAL - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testHealthcareProfessional_RecordNotFound() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'healthcare_professionals' => new List<Object>{
                new Map<String, Object>{ 'id' => 'a3B000000000AAA', 'specialty' => 'Cardiology' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       PERSONAL CONTACT - UPDATE WITH ALL FIELDS
    ============================================================ */
    @IsTest
    static void testPersonalContact_Update_AllFields() {
        Contact c = getOrCreateContact();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'personal_contacts' => new List<Object>{
                new Map<String, Object>{
                    'id'                        => c.Id,
                    'firstName'                 => 'Updated',
                    'lastName'                  => 'ContactUnique',
                    'homePhone'                 => '123456789',
                    'mobilePhone'               => '9876543210',
                    'notes'                     => 'Test notes',
                    'emergencyContact'          => true,
                    'adt_contact'               => true,
                    'authorized_representative' => true,
                    'authorizedToDisclose'      => true,
                    'healthcareSurrogate'       => true,
                    'address'                   => new Map<String, Object>{
                        'street' => '10 Contact Lane', 'city' => 'Pune',
                        'state'  => 'MH', 'zipCode' => '411001', 'country' => 'India'
                    }
                }
            }
        });
        Test.stopTest();

        Contact updated = [SELECT Description FROM Contact WHERE Id = :c.Id];
        System.assertNotEquals(null, updated);
    }

    /* ============================================================
       PERSONAL CONTACT - INSERT SUCCESS
    ============================================================ */
    @IsTest
    static void testPersonalContact_Insert_Success() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'personal_contacts' => new List<Object>{
                new Map<String, Object>{
                    'firstName'                 => 'NewContact',
                    'lastName'                  => 'TestInsert',
                    'email'                     => 'newcontact.' + System.currentTimeMillis() + '@testonly.invalid',
                    'relationship'              => 'Parent',
                    'mobilePhone'               => '8888888888',
                    'emergencyContact'          => true,
                    'adt_contact'               => false,
                    'authorized_representative' => false,
                    'authorizedToDisclose'      => false,
                    'healthcareSurrogate'       => false,
                    'accountId'                 => pa.Id
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       PERSONAL CONTACT - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testPersonalContact_RecordNotFound() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'personal_contacts' => new List<Object>{
                new Map<String, Object>{ 'id' => '003000000000AAA', 'firstName' => 'Ghost', 'lastName' => 'Contact' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       PERSON ACCOUNT - INSERT SUCCESS
    ============================================================ */
    @IsTest
    static void testPersonAccount_Insert_Success() {
        Long   ts          = System.currentTimeMillis();
        String uniqueLast  = 'InsertTest' + ts;
        String uniqueEmail = 'insert.test.' + ts + '@testonly.invalid';

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{
                    'firstName' => 'New', 'lastName' => uniqueLast,
                    'email' => uniqueEmail, 'mobilePhone' => '8888888888'
                }
            }
        });
        Test.stopTest();

        System.assertNotEquals(null, res.responseBody);
    }

    /* ============================================================
       PERSON ACCOUNT - FULL FIELD + ADDRESS MAPPING
    ============================================================ */
    @IsTest
    static void testPersonAccount_FullFieldAndAddressMapping() {
        Account existingPA = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{
                    'id'                     => existingPA.Id,
                    'firstName'              => 'UpdatedFull',
                    'lastName'               => 'PatientUnique',
                    'salutation'             => 'Mr.',
                    'suffix'                 => 'Jr.',
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
                    'status'                 => 'Active',
                    'communicationConsent'   => 'true',
                    'height'                 => '65',
                    'weight'                 => '150',
                    'dateOfBirth'            => '1990-05-15',
                    'signUpDate'             => '2024-01-01',
                    'renewalDate'            => '2025-01-01',
                    'profile_picture'        => 'https://example.com/pic.jpg',
                    'mailingAddress' => new Map<String, Object>{
                        'street' => '12 MG Road', 'city' => 'Delhi',
                        'state'  => 'DL', 'zipCode' => '110001', 'country' => 'India'
                    },
                    'otherAddress' => new Map<String, Object>{
                        'street' => '99 Residency Road', 'city' => 'Bangalore',
                        'state'  => 'KA', 'zipCode' => '560001', 'country' => 'India'
                    }
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       PERSON ACCOUNT - communicationConsent Boolean true
    ============================================================ */
    @IsTest
    static void testPersonAccount_CommunicationConsent_BooleanTrue() {
        Account existingPA = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{
                    'id'                   => existingPA.Id,
                    'firstName'            => 'BoolConsent',
                    'lastName'             => 'PatientUnique',
                    'communicationConsent' => true
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       PERSON ACCOUNT - communicationConsent null
    ============================================================ */
    @IsTest
    static void testPersonAccount_CommunicationConsent_Null() {
        Account existingPA = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{
                    'id'        => existingPA.Id,
                    'firstName' => 'NullConsent',
                    'lastName'  => 'PatientUnique'
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       PERSON ACCOUNT - RECORD NOT FOUND
    ============================================================ */
    @IsTest
    static void testPersonAccount_RecordNotFound() {
        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{ 'id' => '001000000000AAA', 'firstName' => 'Ghost', 'lastName' => 'Account' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       PARSE DECIMAL UTILITY
    ============================================================ */
    @IsTest
    static void testParseDecimal_Variants() {
        Test.startTest();
        System.assertEquals(5.5,  MedicalRecordsUpdateAPI.parseDecimal((Decimal) 5.5, 0.0));
        System.assertEquals(72.5, MedicalRecordsUpdateAPI.parseDecimal('72.5', 0.0));
        System.assertEquals(99.9, MedicalRecordsUpdateAPI.parseDecimal(null, 99.9));
        System.assertEquals(1.0,  MedicalRecordsUpdateAPI.parseDecimal('abc', 1.0));
        System.assertEquals(2.0,  MedicalRecordsUpdateAPI.parseDecimal('   ', 2.0));
        Test.stopTest();
    }

    /* ============================================================
       HEALTH CONDITION - DELETE TRIGGER (single)
    ============================================================ */
    @IsTest
    static void testHealthConditionDeleteTrigger_SingleRecord() {
        createTestDataForTest();
        Account         pa = getOrCreateTestPatient();
        HealthCondition hc = getOrCreateHealthCondition(pa.Id, 'Diabetes');

        Test.startTest();
        delete hc;
        Test.stopTest();

        System.assertEquals(0, [SELECT Id FROM HealthCondition WHERE Id = :hc.Id].size());
    }

    /* ============================================================
       HEALTH CONDITION - DELETE TRIGGER (bulk)
    ============================================================ */
    @IsTest
    static void testHealthConditionDeleteTrigger_BulkRecords() {
        createTestDataForTest();
        Account pa = getOrCreateTestPatient();

        List<HealthCondition> conditionsToDelete = new List<HealthCondition>();
        for (Integer i = 0; i < 3; i++) {
            conditionsToDelete.add(new HealthCondition(ProblemName = 'BulkTestCondition' + i, PatientId = pa.Id));
        }
        safeInsertList(conditionsToDelete);

        Test.startTest();
        delete conditionsToDelete;
        Test.stopTest();

        System.assertEquals(0,
            [SELECT Id FROM HealthCondition WHERE ProblemName LIKE 'BulkTestCondition%'].size());
    }

    /* ============================================================
       HEALTH CONDITION - TRIGGER INSERT / UPDATE
    ============================================================ */
    @IsTest
    static void testHealthConditionTrigger_InsertUpdate() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        HealthCondition newCondition = new HealthCondition(ProblemName = 'TriggerTestCondition', PatientId = pa.Id);
        safeInsert(newCondition);
        newCondition.ProblemName = 'TriggerTestConditionUpdated';
        update newCondition;
        Test.stopTest();

        HealthCondition updated = [SELECT ProblemName FROM HealthCondition WHERE Id = :newCondition.Id];
        System.assertEquals('TriggerTestConditionUpdated', updated.ProblemName);
    }

    /* ============================================================
       GET STATE NAME - code-to-name conversion
    ============================================================ */
    @IsTest
    static void testGetStateName_ValidCode() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        HealthcareFacility fac = new HealthcareFacility(Name = 'StateNameTest', AccountId = pa.Id);
        safeInsert(fac);

        RestResponse res = fireRequest(new Map<String, Object>{
            'healthcare_facilities' => new List<Object>{
                new Map<String, Object>{
                    'id'      => fac.Id,
                    'name'    => 'StateNameTest Updated',
                    'address' => new Map<String, Object>{
                        'street' => '1 State St', 'city' => 'Houston',
                        'state'  => 'TX', 'zipCode' => '77001', 'country' => 'US'
                    }
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MAP ADDRESS - null address input path
    ============================================================ */
    @IsTest
    static void testPersonAccount_NullAddressObjects() {
        Account existingPA = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'basic_details' => new List<Object>{
                new Map<String, Object>{ 'id' => existingPA.Id, 'firstName' => 'NullAddr', 'lastName' => 'PatientUnique' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    /* ============================================================
       MIXED REQUEST - PARTIAL FAILURE
    ============================================================ */
    @IsTest
    static void testMixedRequest_PartialFailure() {
        createTestDataForTest();
        Account         pa = getOrCreateTestPatient();
        HealthCondition hc = getOrCreateHealthCondition(pa.Id, 'Diabetes');

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'medical_history' => new List<Object>{
                new Map<String, Object>{ 'id' => hc.Id, 'medicalProblem' => 'Updated Diabetes' },
                new Map<String, Object>{ 'id' => '0QL000000000AAA', 'medicalProblem' => 'Ghost' }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('succeeded') || body.contains('failed'));
    }

    /* ============================================================
       ALLERGY - INSERT NAME NULL COMBINE FIELD
    ============================================================ */
    @IsTest
    static void testAllergy_Insert_NameNull_CombineField() {
        Account pa = getOrCreateTestPatient();

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{ 'severity' => 'Mild', 'accountId' => pa.Id }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }

    @IsTest
    static void testHealthcareProfessional_UpdateExistingRecord() {
        Account pa = getOrCreateTestPatient();
        HealthcarePractitionerFacility pro = new HealthcarePractitionerFacility(
            Name = 'Dr Test Pro', AccountId = pa.Id
        );
        safeInsert(pro);

        Test.startTest();
        RestResponse res = fireRequest(new Map<String, Object>{
            'healthcare_professionals' => new List<Object>{
                new Map<String, Object>{
                    'id'               => pro.Id,
                    'professionalName' => 'Dr Updated Pro',
                    'name'             => 'Dr Updated Pro Name',
                    'specialty'        => 'Neurology',
                    'email'            => 'updated@testonly.invalid',
                    'faxNumber'        => '0001112222',
                    'website'          => 'https://drupdate.testonly.invalid',
                    'address'          => new Map<String, Object>{
                        'street' => '5 Pro Ave', 'city' => 'Chennai',
                        'state'  => 'TN', 'zipCode' => '600001', 'country' => 'IN'
                    }
                }
            }
        });
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
    }
}