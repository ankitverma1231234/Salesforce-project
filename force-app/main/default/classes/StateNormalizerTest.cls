@isTest
private class StateNormalizerTest {

    @isTest
    static void testValidStateCodes() {
        // Already valid 2-letter codes
        System.assertEquals('CA', StateNormalizer.normalize('CA'));
        System.assertEquals('NY', StateNormalizer.normalize('ny')); // lowercase input
        System.assertEquals('TX', StateNormalizer.normalize(' Tx ')); // with spaces
    }

    @isTest
    static void testFullStateNames() {
        // Full names mapping
        System.assertEquals('CA', StateNormalizer.normalize('California'));
        System.assertEquals('NY', StateNormalizer.normalize('new york'));
        System.assertEquals('TX', StateNormalizer.normalize('  texas  '));
    }

    @isTest
    static void testTerritories() {
        // Bonus territory coverage
        System.assertEquals('DC', StateNormalizer.normalize('District of Columbia'));
        System.assertEquals('PR', StateNormalizer.normalize('Puerto Rico'));
        System.assertEquals('GU', StateNormalizer.normalize('Guam'));
        System.assertEquals('VI', StateNormalizer.normalize('Virgin Islands'));
    }

    @isTest
    static void testInvalidInputs() {
        // Invalid values
        System.assertEquals(null, StateNormalizer.normalize('XYZ'));
        System.assertEquals(null, StateNormalizer.normalize('Californi')); // typo
        System.assertEquals(null, StateNormalizer.normalize('123'));
    }

    @isTest
    static void testBlankAndNull() {
        // Blank and null handling
        System.assertEquals(null, StateNormalizer.normalize(null));
        System.assertEquals(null, StateNormalizer.normalize(''));
        System.assertEquals(null, StateNormalizer.normalize('   '));
    }

    @isTest
    static void testEdgeCases() {
        // Mixed edge cases
        System.assertEquals(null, StateNormalizer.normalize('C')); // single char
        System.assertEquals(null, StateNormalizer.normalize('CAL')); // 3-char invalid
        System.assertEquals('FL', StateNormalizer.normalize('fL')); // mixed case valid
    }
}