@IsTest
global class MetriportMockCallout implements HttpCalloutMock {

    global HttpResponse respond(HttpRequest req) {

        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('{"status":"success"}');

        return res;
    }
}