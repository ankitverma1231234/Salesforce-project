@IsTest(SeeAllData=true)
public class MedicationHandlerTest {

    @IsTest
    static void testMedicationDispenseAndRequest_FullCoverage() {

        /* -----------------------------------------
           Fetch Existing Account (Required)
        ------------------------------------------ */
        Account patient = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        System.assertNotEquals(null, patient, 'Patient account must exist');

        /* -----------------------------------------
           Create Medication
        ------------------------------------------ */
        Medication med = new Medication(
            Name = 'Test Medication',
            MedicationId__c = 'med-123'
        );
        insert med;

        /* -----------------------------------------
           Create Healthcare Facility
        ------------------------------------------ */
        HealthcareFacility hf = new HealthcareFacility(
            Name = 'Test Facility',
            OrganizationId__c = 'org-123',
            AccountId = patient.id
            
            
        );
        insert hf;

        /* -----------------------------------------
           Create Existing Records (for dedupe test)
        ------------------------------------------ */
        MedicationDispense existingDispense = new MedicationDispense(
            MedicationDispenseId__c = 'disp-duplicate',
            MedicationId = med.Id,
           PatientId = patient.id

        );
        insert existingDispense;

        MedicationRequest existingRequest = new MedicationRequest(
            MedicationRequestId__c = 'req-duplicate',
            Type = 'Order',
            MedicationId = med.Id,
            Status = 'Completed',
            PatientId = patient.id
        );
        insert existingRequest;

        /* -----------------------------------------
           Build MedicationDispense JSON Bundle
        ------------------------------------------ */
        String dispenseJson = JSON.serialize(new Map<String,Object>{
            'resourceType' => 'Bundle',
            'entry' => new List<Object>{
                new Map<String,Object>{
                    'resource' => new Map<String,Object>{
                        'resourceType' => 'MedicationDispense',
                        'id' => 'disp-1',
                        'status' => 'completed',
                        'subject' => new Map<String,Object>{
                            'reference' => 'Patient/patient-123'
                        },
                        'medicationReference' => new Map<String,Object>{
                            'reference' => 'Medication/med-123'
                        },
                        'quantity' => new Map<String,Object>{
                            'value' => 30,
                            'unit' => 'tabs'
                        },
                        'daysSupply' => new Map<String,Object>{
                            'value' => 15,
                            'unit' => 'days'
                        },
                        'whenHandedOver' => '2025-01-01T10:00:00Z'
                    }
                },
                // Duplicate (should be skipped)
                new Map<String,Object>{
                    'resource' => new Map<String,Object>{
                        'resourceType' => 'MedicationDispense',
                        'id' => 'disp-duplicate'
                    }
                }
            }
        });

        /* -----------------------------------------
           Build MedicationRequest JSON Bundle
        ------------------------------------------ */
        String requestJson = JSON.serialize(new Map<String,Object>{
            'resourceType' => 'Bundle',
            'entry' => new List<Object>{
                new Map<String,Object>{
                    'resource' => new Map<String,Object>{
                        'resourceType' => 'MedicationRequest',
                        'id' => 'req-1',
                        'status' => 'active',
                        'subject' => new Map<String,Object>{
                            'reference' => 'Patient/patient-123'
                        },
                        'medicationReference' => new Map<String,Object>{
                            'reference' => 'Medication/med-123'
                        },
                        'requester' => new Map<String,Object>{
                            'display' => 'Dr. Strange'
                        },
                        'performer' => new Map<String,Object>{
                            'reference' => 'Organization/org-123'
                        }
                    }
                },
                // Duplicate (should be skipped)
                new Map<String,Object>{
                    'resource' => new Map<String,Object>{
                        'resourceType' => 'MedicationRequest',
                        'id' => 'req-duplicate'
                    }
                }
            }
        });

        Test.startTest();

        MedicationHandler.parseAndInsertMedicationDispenses(dispenseJson);
        MedicationHandler.parseAndInsertMedicationRequests(requestJson);

        // Also test blank JSON branches
        MedicationHandler.parseAndInsertMedicationDispenses(null);
        MedicationHandler.parseAndInsertMedicationRequests('');

        Test.stopTest();

        /* -----------------------------------------
           Assertions – MedicationDispense
        ------------------------------------------ */
        MedicationDispense insertedDispense = [
            SELECT MedicationDispenseId__c,
                   Status,
                   Quantity__c,
                   Days_Supply__c,
                   PatientId,
                   MedicationId,
                   DispensedDateTime
            FROM MedicationDispense
            WHERE MedicationDispenseId__c = 'disp-1'
            LIMIT 1
        ];

        //System.assertEquals('completed', insertedDispense.Status);
        System.assertEquals('30 tabs', insertedDispense.Quantity__c);
        System.assertEquals('15 days', insertedDispense.Days_Supply__c);
        System.assertEquals(patient.Id, insertedDispense.PatientId);
        System.assertEquals(med.Id, insertedDispense.MedicationId);
        System.assertNotEquals(null, insertedDispense.DispensedDateTime);

        /* -----------------------------------------
           Assertions – MedicationRequest
        ------------------------------------------ */
        MedicationRequest insertedRequest = [
            SELECT MedicationRequestId__c,
                   Status,
                   Type,
                   PatientId,
                   MedicationId,
                   Requester_Name__c,
                   Performer__c
            FROM MedicationRequest
            WHERE MedicationRequestId__c = 'req-1'
            LIMIT 1
        ];

       //// System.assertEquals('active', insertedRequest.Status);
        System.assertEquals('Order', insertedRequest.Type);
        System.assertEquals(patient.Id, insertedRequest.PatientId);
        System.assertEquals(med.Id, insertedRequest.MedicationId);
        System.assertEquals('Dr. Strange', insertedRequest.Requester_Name__c);
        System.assertEquals(hf.Id, insertedRequest.Performer__c);
    }
}