public without sharing class AccountAccessTokenUtil {

    public static String generateToken() {
        Blob raw = Crypto.generateAesKey(256);
        return EncodingUtil.convertToHex(raw);
    }

  
    public static String generateVerificationCode() {
        // getRandomInteger returns a signed 32-bit int; take abs and mod into 000000-999999.
        Integer raw = Crypto.getRandomInteger();
        Integer code = Math.mod(Math.abs(raw), 1000000);
        return String.valueOf(code).leftPad(6, '0');
    }
}