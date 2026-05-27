@isTest
global class StripeRefundMock implements HttpCalloutMock {
    private String refundNote;

    // No‑argument constructor
    public StripeRefundMock() {
        this.refundNote = null;
    }
    
    // Parameterized constructor
    public StripeRefundMock(String refundNote) {
        this.refundNote = refundNote;
    }

    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content‑Type', 'application/json');

        if (req.getBody().contains('payment_intent=pi_test_success')) {
            res.setStatusCode(200);
            String body = '{'
                        + '"id": "re_1234567890",'
                        + '"status": "succeeded",'
                        + '"amount": 1000,'
                        + '"currency": "usd"';
            if (refundNote != null) {
                body += ', "metadata": {"refund_note": "' + String.escapeSingleQuotes(refundNote) + '"}';
            }
            body += '}';
            res.setBody(body);
        }
        else if (req.getBody().contains('payment_intent=pi_test_error')) {
            res.setStatusCode(400);
            res.setBody('{'
                        + '"error": {"message": "The payment intent does not exist."}'
                        + '}');
        }
        else {
            res.setStatusCode(200);
            res.setBody('{}');
        }

        return res;
    }
}