@RestResource(urlMapping='/public/file-download/*')
global without sharing class FileDownloadAPI {

    @HttpGet
    global static void download() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String versionId;

        // Case 1: /file-download/068xxxx
        if (req.requestURI.contains('/public/file-download/')) {
            versionId = req.requestURI.substringAfterLast('/');
        }

        // Case 2: /file-download?ids=068xxxx
        if (String.isBlank(versionId)) {
            versionId = req.params.get('ids');
        }

        if (String.isBlank(versionId) || !versionId.startsWith('068')) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('Invalid or missing ContentVersion Id');
            return;
        }
        ContentVersion cv = [
            SELECT VersionData, Title, FileExtension
            FROM ContentVersion
            WHERE Id = :versionId
            LIMIT 1
        ];

        res.addHeader('Access-Control-Allow-Origin', '*');
        res.addHeader(
            'Content-Disposition',
            'attachment; filename="' +
            cv.Title + '.' + cv.FileExtension + '"'
        );
        res.addHeader('Content-Type', 'application/octet-stream');
        res.responseBody = cv.VersionData;
        res.statusCode = 200;
    }
}