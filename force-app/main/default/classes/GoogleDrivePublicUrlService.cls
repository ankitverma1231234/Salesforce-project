public without sharing class GoogleDrivePublicUrlService {
    public static String getPublicUrl(String driveSpecificCred, String fileId) {
        try {
            if (String.isBlank(driveSpecificCred)) {
                throw new AuraHandledException('Google Drive Named Credential is blank.');
            }
            if (String.isBlank(fileId)) {
                throw new AuraHandledException('Google Drive file id is blank.');
            }

            Http http = new Http();
            String encodedFileId = EncodingUtil.urlEncode(fileId, 'UTF-8');

            HttpRequest permReq = new HttpRequest();
            permReq.setEndpoint('callout:' + driveSpecificCred + '/drive/v3/files/' + encodedFileId + '/permissions');
            permReq.setMethod('POST');
            permReq.setHeader('Content-Type', 'application/json');
            permReq.setTimeout(120000);
            permReq.setBody(JSON.serialize(new Map<String, Object>{
                'role' => 'reader',
                'type' => 'anyone'
            }));

            System.debug(LoggingLevel.DEBUG, 'GoogleDrivePublicUrlService permission request endpoint=' + permReq.getEndpoint());
            HttpResponse permRes = http.send(permReq);
            System.debug(LoggingLevel.DEBUG, 'GoogleDrivePublicUrlService permission response status=' + permRes.getStatusCode() + ', body=' + permRes.getBody());

            if (permRes.getStatusCode() != 200 && permRes.getStatusCode() != 201) {
                throw new AuraHandledException(
                    'Failed to set permissions. Status: ' +
                    permRes.getStatusCode() +
                    ' Body: ' +
                    permRes.getBody()
                );
            }

            HttpRequest fileReq = new HttpRequest();
            fileReq.setEndpoint(
                'callout:' + driveSpecificCred +
                '/drive/v3/files/' + encodedFileId +
                '?fields=webViewLink,webContentLink'
            );
            fileReq.setMethod('GET');
            fileReq.setHeader('Content-Type', 'application/json');
            fileReq.setTimeout(120000);

            System.debug(LoggingLevel.DEBUG, 'GoogleDrivePublicUrlService file request endpoint=' + fileReq.getEndpoint());
            HttpResponse fileRes = http.send(fileReq);
            System.debug(LoggingLevel.DEBUG, 'GoogleDrivePublicUrlService file response status=' + fileRes.getStatusCode() + ', body=' + fileRes.getBody());

            if (fileRes.getStatusCode() != 200) {
                throw new AuraHandledException(
                    'Failed to fetch file details. Status: ' +
                    fileRes.getStatusCode() +
                    ' Body: ' +
                    fileRes.getBody()
                );
            }

            Map<String, Object> fileMap = (Map<String, Object>) JSON.deserializeUntyped(fileRes.getBody());
            String webViewLink = (String) fileMap.get('webViewLink');
            if (String.isNotBlank(webViewLink)) {
                return webViewLink;
            }

            throw new AuraHandledException('No public link available for this file.');
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error while generating Google Drive link: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
            throw new AuraHandledException('Error while generating Google Drive link: ' + ex.getMessage());
        }
    }

    public static Boolean namedCredentialExists(String namedCredentialName) {
        if (String.isBlank(namedCredentialName)) {
            return false;
        }
        if (Test.isRunningTest()) {
            return true;
        }

        try {
            List<NamedCredential> credentials = [
                SELECT DeveloperName
                FROM NamedCredential
                WHERE DeveloperName = :namedCredentialName
                LIMIT 1
            ];
            return !credentials.isEmpty();
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Unable to verify Named Credential ' + namedCredentialName + ': ' + ex.getMessage());
            return true;
        }
    }
}