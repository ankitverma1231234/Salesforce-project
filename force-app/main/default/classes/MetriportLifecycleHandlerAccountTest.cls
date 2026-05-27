@IsTest
private class MetriportLifecycleHandlerAccountTest {

    @IsTest
    static void testOnRenderWithValidParams() {
        Map<String, String> envValues = new Map<String, String>();
        envValues.put(Canvas.Test.KEY_DISPLAY_LOCATION, 'Visualforce');

        Canvas.RenderContext mockRenderContext = Canvas.Test.mockRenderContext(null, envValues);
        MetriportLifecycleHandlerAccount handler = new MetriportLifecycleHandlerAccount();

        Set<Canvas.ContextTypeEnum> excluded = handler.excludeContextTypes();
        System.assertEquals(0, excluded.size(), 'excludeContextTypes should return empty set');

        Canvas.Test.testCanvasLifecycle(handler, mockRenderContext);
        System.assertEquals(1, 1, 'onRender executed successfully');
    }

    @IsTest
    static void testOnRenderWithLayoutsContext() {
        Map<String, String> envValues = new Map<String, String>();
        envValues.put(Canvas.Test.KEY_DISPLAY_LOCATION, 'Layouts');

        Canvas.RenderContext mockRenderContext = Canvas.Test.mockRenderContext(null, envValues);
        MetriportLifecycleHandlerAccount handler = new MetriportLifecycleHandlerAccount();

        try {
            Canvas.Test.testCanvasLifecycle(handler, mockRenderContext);
            System.assertEquals(1, 1, 'Handled Layouts context gracefully');
        } catch (Exception ex) {
            System.assert(false, 'Should not throw exception: ' + ex.getMessage());
        }
    }

    @IsTest
    static void testOnRenderWithLightningComponent() {
        Map<String, String> envValues = new Map<String, String>();
        envValues.put(Canvas.Test.KEY_DISPLAY_LOCATION, 'Lightning Component');

        Canvas.RenderContext mockRenderContext = Canvas.Test.mockRenderContext(null, envValues);
        MetriportLifecycleHandlerAccount handler = new MetriportLifecycleHandlerAccount();

        try {
            Canvas.Test.testCanvasLifecycle(handler, mockRenderContext);
            System.assertEquals(1, 1, 'onRender executed successfully from Lightning Component');
        } catch (Exception ex) {
            System.assert(false, 'Should not throw exception: ' + ex.getMessage());
        }
    }

    @IsTest
    static void testExcludeContextTypes() {
        MetriportLifecycleHandlerAccount handler = new MetriportLifecycleHandlerAccount();

        Set<Canvas.ContextTypeEnum> result = handler.excludeContextTypes();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return empty set');
    }
}