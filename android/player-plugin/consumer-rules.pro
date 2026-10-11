# Called by GDScript through JavaClassWrapper, not visible to shrinker analysis.
-keep class org.vrpassthroughplayer.plugin.XrUiSurfaceBridge {
    public static int contextGeneration();
    public static void attachSurface(android.view.Surface);
    public static void submitTexture(int, int, int, int, long);
    public static void setEnabled(boolean);
    public static java.lang.String status();
}
