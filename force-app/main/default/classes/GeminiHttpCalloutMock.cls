@isTest
public class GeminiHttpCalloutMock implements HttpCalloutMock {
    public Boolean isErrorMsg = false;
    public Integer statusCode = 200;
    public String  mockJsonResponse = '';

    // Constructor to quickly allow changing responses
    public GeminiHttpCalloutMock(Boolean isError, Integer code, String specificJson) {
        this.isErrorMsg = isError;
        this.statusCode = code;
        this.mockJsonResponse = specificJson;
    }

    public GeminiHttpCalloutMock() {
        // Build a default successful mock mimicking the Gemini response format
        String bundleJson = '{"sections": {"summary": "Mock summary", "chiefComplaint": "<ul><li>Headache</li></ul>"}, "tagGroups": [], "keyFields": []}';
        
        // This simulates the actual Gemini response payload wrapping the bundle 
        this.mockJsonResponse = '{ ' +
            '"candidates": [ { ' +
                '"content": { ' +
                    '"parts": [ { "text": "' + bundleJson.replace('"', '\\"') + '" } ] ' +
                '} ' +
            '} ] ' +
        '}';
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        
        if (isErrorMsg || statusCode != 200) {
            res.setBody('{"error": {"message": "Bad Request"}}');
            res.setStatusCode(statusCode != 200 ? statusCode : 400);
        } else {
            res.setBody(String.isNotBlank(mockJsonResponse) ? mockJsonResponse : '{}');
            res.setStatusCode(200);
        }
        
        return res;
    }
}