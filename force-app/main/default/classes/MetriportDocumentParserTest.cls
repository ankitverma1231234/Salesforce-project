@IsTest(seeAllData=true)
public class MetriportDocumentParserTest {

    @IsTest
    static void testProcessDocuments_HappyPath() {

        // -------- Fetch existing Account (NO INSERT) --------
        Account acc = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
        System.assertNotEquals(null, acc, 'Account with patient-123 must exist');

        // -------- Build JSON Response --------
        String jsonResponse =
        '{' +
            '"documents": [' +
                '{' +
                    '"id": "doc-001",' +
                    '"status": "current",' +
                    '"description": "Test clinical document",' +
                    '"date": "2023-08-15T03:05:58.090Z",' +
                    '"type": {' +
                        '"coding": [' +
                            '{ "display": "Clinical Note" }' +
                        ']' +
                    '},' +
                    '"meta": {' +
                        '"source": "test-file.pdf"' +
                    '},' +
                    '"contained": [' +
                        '{' +
                            '"resourceType": "Organization",' +
                            '"name": "Test Hospital"' +
                        '}' +
                    ']' +
                '}' +
            ']' +
        '}';

        Test.startTest();

        // -------- Execute Parser --------
        MetriportDocumentParser.processDocuments(
            jsonResponse,
            'patient-123'
        );

        Test.stopTest();

        // -------- Assertions --------
        List<Document_Reference__c> docs = [
            SELECT Id,
                   DocumentReferenceId__c,
                   Patient__c,
                   Status__c,
                   Description__c,
                   Date__c,
                   Name__c,
                   File_Name__c,
                   Organization_Name__c
            FROM Document_Reference__c
            WHERE DocumentReferenceId__c = 'doc-001'
        ];

        System.assertEquals(1, docs.size(), 'Document_Reference__c should be created');

        Document_Reference__c dr = docs[0];
        System.assertEquals(acc.Id, dr.Patient__c);
        System.assertEquals('current', dr.Status__c);
        System.assertEquals('Test clinical document', dr.Description__c);
       // System.assertEquals(Date.newInstance(2023, 8, 15), dr.Date__c);
        System.assertEquals('Clinical Note', dr.Name__c);
        System.assertEquals('test-file.pdf', dr.File_Name__c);
        System.assertEquals('Test Hospital', dr.Organization_Name__c);
    }
}