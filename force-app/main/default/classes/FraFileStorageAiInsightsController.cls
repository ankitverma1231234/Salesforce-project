public with sharing class FraFileStorageAiInsightsController {
    @AuraEnabled(cacheable=true)
    public static FraFileStorageAiInsightsService.InsightsResponse getInsights(Id fileStorageId) {
        return FraFileStorageAiInsightsService.getInsights(fileStorageId);
    }

    @AuraEnabled
    public static String askQuestion(Id fileStorageId, String question) {
        return FraFileStorageAiInsightsService.askQuestion(fileStorageId, question);
    }
}