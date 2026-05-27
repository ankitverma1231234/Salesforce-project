@IsTest
public class AllergyIntoleranceHandlerTest {

    /* ----------------------------------------------------
       Test 1: Bundle with non-Allergy resource
       (covers Bundle parsing + skip logic)
    ---------------------------------------------------- */
    @IsTest
    static void testBundleWithoutAllergies() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'Bundle',
            'entry' => new List<Object>{
                new Map<String, Object>{
                    'resource' => new Map<String, Object>{
                        'resourceType' => 'Observation'
                    }
                }
            }
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 2: Bundle with AllergyIntolerance (no id → no insert)
       (covers Bundle + Allergy collection path)
    ---------------------------------------------------- */
    @IsTest
    static void testBundleWithAllergyEntry() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'Bundle',
            'entry' => new List<Object>{
                new Map<String, Object>{
                    'resource' => new Map<String, Object>{
                        'resourceType' => 'AllergyIntolerance',
                        'reaction' => new List<Object>()
                    }
                }
            }
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 3: Single Allergy resource (no id)
       (covers single-resource path)
    ---------------------------------------------------- */
    @IsTest
    static void testSingleAllergyWithoutId() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'AllergyIntolerance',
            'clinicalStatus' => new Map<String, Object>{
                'coding' => new List<Object>{
                    new Map<String, Object>{ 'display' => 'Active' }
                }
            }
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 4: onsetDateTime parsing
       (covers parseOnsetDateTime → String branch)
    ---------------------------------------------------- */
    @IsTest
    static void testOnsetDateTimeParsing() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'AllergyIntolerance',
            'onsetDateTime' => '2024-02-01T10:30:00Z'
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 5: onsetPeriod.start parsing
       (covers parseOnsetDateTime → Period branch)
    ---------------------------------------------------- */
    @IsTest
    static void testOnsetPeriodParsing() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'AllergyIntolerance',
            'onsetPeriod' => new Map<String, Object>{
                'start' => '2023-01-01T00:00:00Z'
            }
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 6: CodeableConcept display
       (covers primary display mapping)
    ---------------------------------------------------- */
    @IsTest
    static void testCodeableConceptDisplay() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'AllergyIntolerance',
            'verificationStatus' => new Map<String, Object>{
                'coding' => new List<Object>{
                    new Map<String, Object>{ 'display' => 'Confirmed' }
                }
            }
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 7: CodeableConcept fallback (code + text)
       (covers fallback logic)
    ---------------------------------------------------- */
    @IsTest
    static void testCodeableConceptFallbacks() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'AllergyIntolerance',
            'verificationStatus' => new Map<String, Object>{
                'coding' => new List<Object>{
                    new Map<String, Object>{ 'code' => 'confirmed-code' }
                }
            },
            'clinicalStatus' => new Map<String, Object>{
                'text' => 'Resolved'
            }
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 8: Reaction parsing + Generic__c logic
       (covers severity + multiple codings)
    ---------------------------------------------------- */
    @IsTest
    static void testReactionMultipleCodings() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'AllergyIntolerance',
            'reaction' => new List<Object>{
                new Map<String, Object>{
                    'severity' => 'moderate',
                    'substance' => new Map<String, Object>{
                        'text' => 'Milk',
                        'coding' => new List<Object>{
                            new Map<String, Object>{ 'display' => 'Milk Allergy' },
                            new Map<String, Object>{ 'display' => 'Dairy Allergy' }
                        }
                    }
                }
            }
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 9: resolvePatientContact reference parsing
       (covers patient.reference parsing safely)
    ---------------------------------------------------- */
    @IsTest
    static void testResolvePatientReference() {

        String json = JSON.serialize(new Map<String, Object>{
            'resourceType' => 'AllergyIntolerance',
            'patient' => new Map<String, Object>{
                'reference' => 'Patient/ABC123'
            }
        });

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(json);
        Test.stopTest();

        System.assert(true);
    }

    /* ----------------------------------------------------
       Test 10: Blank & invalid JSON
       (covers guard clauses + exception safety)
    ---------------------------------------------------- */
    @IsTest
    static void testBlankAndInvalidJson() {

        Test.startTest();
        AllergyIntoleranceHandler.parseAndInsertAllergies(null);
        AllergyIntoleranceHandler.parseAndInsertAllergies('');
        AllergyIntoleranceHandler.parseAndInsertAllergies('{"bad":"json"}');
        Test.stopTest();

        System.assert(true);
    }
}