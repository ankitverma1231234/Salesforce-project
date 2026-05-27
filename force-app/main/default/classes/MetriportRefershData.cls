@RestResource(urlMapping='/metripoint/refresh/*')
global without sharing class MetriportRefershData {

    global class RefreshRequest {
        global String patientId { get; set; }
    }

    global class RefreshResponse {
        global Boolean success   { get; set; }
        global String  message   { get; set; }
        global String  patientId { get; set; }
        global String  errorCode { get; set; }

        global RefreshResponse(Boolean success, String message, String patientId) {
            this.success   = success;
            this.message   = message;
            this.patientId = patientId;
        }
    }

    @HttpPost
    global static void handleRefresh() {

        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        res.addHeader('Content-Type', 'application/json');

        try {
            // ── 1. Validate body ──────────────────────────────────────────────
            if (req.requestBody == null || req.requestBody.size() == 0) {
                sendError(res, 400, 'MISSING_BODY', 'Request body is required.');
                return;
            }

            // ── 2. Deserialize ────────────────────────────────────────────────
            RefreshRequest payload = (RefreshRequest)
                JSON.deserialize(req.requestBody.toString(), RefreshRequest.class);

            // ── 3. Validate patientId presence ────────────────────────────────
            if (String.isBlank(payload.patientId)) {
                sendError(res, 400, 'MISSING_PATIENT_ID', 'patientId is required.');
                return;
            }

            // ── 4. Validate patientId format (15 or 18 alphanumeric chars) ────
            if (!Pattern.matches('[a-zA-Z0-9]{15}|[a-zA-Z0-9]{18}', payload.patientId)) {
                sendError(res, 400, 'INVALID_PATIENT_ID', 'patientId format is invalid.');
                return;
            }

            // ── 5. Lookup Account ─────────────────────────────────────────────
            List<Account> accounts = [
                SELECT Id, Metriport_Patient_Id__c
                FROM   Account
                WHERE  Id = :payload.patientId
                LIMIT  1
            ];

            if (accounts.isEmpty()) {
                sendError(res, 404, 'PATIENT_NOT_FOUND',
                          'No account found for the provided patientId.');
                return;
            }

            String metriportPatientId = accounts[0].Metriport_Patient_Id__c;

            if (String.isBlank(metriportPatientId)) {
                sendError(res, 422, 'MISSING_METRIPORT_ID',
                          'Account does not have a Metriport Patient ID linked.');
                return;
            }

            MetripointfetchPateintDetails.startConsolidatedQuery(metriportPatientId);

            res.statusCode   = 202;
            res.responseBody = Blob.valueOf(
                JSON.serialize(
                    new RefreshResponse(
                        true,
                        'Refresh request accepted. Data will be updated shortly.',
                        payload.patientId
                    )
                )
            );

        } catch (JSONException je) {
            System.debug(LoggingLevel.ERROR, 'JSON parse error: ' + je.getMessage());
            sendError(res, 400, 'INVALID_JSON', 'Request body is not valid JSON.');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                         'Unexpected error: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            sendError(res, 500, 'INTERNAL_ERROR', 'An unexpected error occurred.');
        }
    }

    private static void sendError(RestResponse res, Integer statusCode,
                                   String errorCode, String message) {
        res.statusCode   = statusCode;
        res.responseBody = Blob.valueOf(
            JSON.serialize(new Map<String, Object>{
                'success'   => false,
                'errorCode' => errorCode,
                'message'   => message
            })
        );
    }
}