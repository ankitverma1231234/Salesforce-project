@IsTest
private class AccountAccessTokenUtilTest {

    @IsTest
    static void tokenIsHexAnd64Chars() {
        String t = AccountAccessTokenUtil.generateToken();
        System.assertNotEquals(null, t);
        System.assertEquals(64, t.length(), 'Token should be 64 hex chars (32 bytes)');
        System.assert(Pattern.matches('^[0-9a-fA-F]{64}$', t), 'Token should be hex');
    }

    @IsTest
    static void tokensAreUnique() {
        Set<String> seen = new Set<String>();
        for (Integer i = 0; i < 25; i++) {
            seen.add(AccountAccessTokenUtil.generateToken());
        }
        System.assertEquals(25, seen.size(), 'Tokens must be unique');
    }

    @IsTest
    static void codeIs6Digits() {
        for (Integer i = 0; i < 20; i++) {
            String c = AccountAccessTokenUtil.generateVerificationCode();
            System.assertEquals(6, c.length());
            System.assert(Pattern.matches('^[0-9]{6}$', c), 'Code should be 6 digits: ' + c);
        }
    }
}