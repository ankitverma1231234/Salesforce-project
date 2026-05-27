public class MetriportLifecycleHandlerAccount implements Canvas.CanvasLifecycleHandler {
    
    public Set<Canvas.ContextTypeEnum> excludeContextTypes(){
        Set<Canvas.ContextTypeEnum> excluded = new Set<Canvas.ContextTypeEnum>();
        return excluded;
    }
    
    public void onRender(Canvas.RenderContext renderContext){
        Canvas.ApplicationContext appContext = renderContext.getApplicationContext();
        Canvas.EnvironmentContext envContext = renderContext.getEnvironmentContext();
        
        if (envContext != null && appContext != null) {
            Canvas.EnvironmentContext env = renderContext.getEnvironmentContext();
            Map<String, Object> currentParams = (Map<String, Object>) JSON.deserializeUntyped(env.getParametersAsJSON());
            
            if (currentParams != null) {
                Object patientIdObj = currentParams.get('patient_id');
                Object clientIdObj = currentParams.get('client_id');
                
                if (patientIdObj != null && clientIdObj != null) {
                    String patientId = String.valueOf(patientIdObj);
                    String clientId = String.valueOf(clientIdObj);
                    String newCanvasPath = '/salesforce/launch?patientId=' + patientId + '&clientId=' + clientId;
                    appContext.setCanvasUrlPath(newCanvasPath);
                }
            } else {
                System.debug('No parameters found in environment context');
            }
        }
    }
}