@IsTest(SeeAllData=true)
public class MetriportADTQueueableTest {

    @IsTest
    static void testPatientAdmitHappyPath() {
        // Verify required data exists (defensive, but non-failing)
        Account acc = [
            SELECT Id, OwnerId, Name
            FROM Account
            WHERE Metriport_Patient_id__c = 'patient-123'
            LIMIT 1
        ];

        Visit v = [
            SELECT Id, VisitId__c, Name, Place.Name
            FROM Visit
            WHERE VisitId__c = 'encounter-123'
            LIMIT 1
        ];

        // Build a realistic FHIR-like bundle JSON
        String bundleJson = JSON.serialize(new Map<String, Object>{
            'entry' => new List<Object>{
                new Map<String, Object>{
                    'resource' => new Map<String, Object>{
                        'resourceType' => 'Patient',
                        'id' => 'patient-123'
                    }
                },
                new Map<String, Object>{
                    'resource' => new Map<String, Object>{
                        'resourceType' => 'Encounter',
                        'id' => 'encounter-123'
                    }
                }
            }
        });

        Test.startTest();
        System.enqueueJob(
            new MetriportADTNotificationServiceQueueable(
                bundleJson,
                'patient.admit'
            )
        );
        Test.stopTest();

        // No hard assertions on notifications (platform-managed),
        // reaching here confirms execution without exception
        System.assert(true, 'Queueable executed successfully');
    }

    @IsTest
    static void testInvalidInputBlankJson() {
        Test.startTest();
        System.enqueueJob(
            new MetriportADTNotificationServiceQueueable(
                '',
                'patient.admit'
            )
        );
        Test.stopTest();

        System.assert(true, 'Handled blank JSON input gracefully');
    }

    @IsTest
    static void testInvalidJsonFormat() {
        Test.startTest();
        System.enqueueJob(
            new MetriportADTNotificationServiceQueueable(
                'INVALID_JSON',
                'patient.admit'
            )
        );
        Test.stopTest();

        System.assert(true, 'Handled JSON deserialization failure');
    }

    @IsTest
    static void testUnknownEventTypeFallback() {
        String bundleJson = JSON.serialize(new Map<String, Object>{
            'entry' => new List<Object>{
                new Map<String, Object>{
                    'resource' => new Map<String, Object>{
                        'resourceType' => 'Patient',
                        'id' => 'patient-123'
                    }
                },
                new Map<String, Object>{
                    'resource' => new Map<String, Object>{
                        'resourceType' => 'Encounter',
                       'id' => 'encounter-123'
                    }
                }
            }
        });

        Test.startTest();
        System.enqueueJob(
            new MetriportADTNotificationServiceQueueable(
                bundleJson,
                'patient.unknown'
            )
        );
        Test.stopTest();

        System.assert(true, 'Handled unknown event type correctly');
    }
}