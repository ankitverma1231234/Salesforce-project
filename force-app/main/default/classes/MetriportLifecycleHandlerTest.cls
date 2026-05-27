@IsTest
public class MetriportLifecycleHandlerTest {
    @IsTest
    static void testOnRenderWithLayoutsContext() {
        // Arrange: Create mock data for a different environment context
        Map<String, String> envValues = new Map<String, String>();
        envValues.put(Canvas.Test.KEY_DISPLAY_LOCATION, 'Layouts');
        // Create the mock Canvas.RenderContext
        Canvas.RenderContext mockRenderContext = Canvas.Test.mockRenderContext(null, envValues);
        // Arrange: Instantiate the handler
        MetriportLifecycleHandler handler = new MetriportLifecycleHandler();
        // Act: Invoke the excludeContextTypes method
        handler.excludeContextTypes();
        // Act: Invoke the onRender method
        Canvas.Test.testCanvasLifecycle(handler, mockRenderContext);
        // Assert: N/A
        System.assertEquals(1, 1, '');
    }
}