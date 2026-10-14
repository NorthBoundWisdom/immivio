package org.vrpassthroughplayer.probe;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ColorSpace;
import android.graphics.ImageDecoder;
import android.graphics.PixelFormat;
import android.media.MediaMetadataRetriever;

import java.io.File;
import java.util.zip.CRC32;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Standalone shell VM probe: framework HEIF decoding only, no APK, Godot, XR or depth model.
 */
public final class HeifDecodeProbe {
    public static void main(String[] paths) throws Exception {
        JSONArray results = new JSONArray();
        for (String path : paths) {
            File file = new File(path);
            for (String mode : new String[]{"decoder", "low_ram", "argb32", "factory", "retriever"})
                for (boolean scaled : new boolean[]{false, true}) {
                    JSONObject result = new JSONObject().put("file", file.getName()).put("scaled", scaled).put("mode", mode);
                    long started = System.nanoTime();
                    Bitmap bitmap = null;
                    try {
                        if (mode.equals("factory")) {
                            BitmapFactory.Options options = new BitmapFactory.Options();
                            options.inPreferredConfig = Bitmap.Config.ARGB_8888;
                            options.inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB);
                            options.inSampleSize = scaled ? 2 : 1;
                            bitmap = BitmapFactory.decodeFile(path, options);
                            if (bitmap == null)
                                throw new IllegalStateException("BitmapFactory returned null");
                        } else if (mode.equals("retriever")) {
                            MediaMetadataRetriever retriever = new MediaMetadataRetriever();
                            try {
                                retriever.setDataSource(path);
                                MediaMetadataRetriever.BitmapParams params = new MediaMetadataRetriever.BitmapParams();
                                params.setPreferredConfig(Bitmap.Config.ARGB_8888);
                                bitmap = retriever.getPrimaryImage(params);
                                if (bitmap == null)
                                    throw new IllegalStateException("Retriever returned null");
                                if (scaled) {
                                    Bitmap smaller = Bitmap.createScaledBitmap(bitmap, Math.max(1, bitmap.getWidth() / 2), Math.max(1, bitmap.getHeight() / 2), true);
                                    if (smaller != bitmap) bitmap.recycle();
                                    bitmap = smaller;
                                }
                            } finally {
                                retriever.release();
                            }
                        } else
                            bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(file), (decoder, info, source) -> {
                                try {
                                    result.put("header_width", info.getSize().getWidth()).put("header_height", info.getSize().getHeight());
                                } catch (Exception error) {
                                    throw new RuntimeException(error);
                                }
                                decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
                                if (mode.equals("low_ram") || mode.equals("argb32"))
                                    decoder.setMemorySizePolicy(ImageDecoder.MEMORY_POLICY_LOW_RAM);
                                if (mode.equals("argb32"))
                                    decoder.setPostProcessor(canvas -> PixelFormat.UNKNOWN);
                                decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB));
                                if (scaled)
                                    decoder.setTargetSize(Math.max(1, info.getSize().getWidth() / 2), Math.max(1, info.getSize().getHeight() / 2));
                            });
                        result.put("state", "ready").put("width", bitmap.getWidth()).put("height", bitmap.getHeight())
                                .put("config", String.valueOf(bitmap.getConfig()));
                        int[] row = new int[bitmap.getWidth()];
                        CRC32 crc = new CRC32();
                        for (int y = 0; y < bitmap.getHeight(); y++) {
                            bitmap.getPixels(row, 0, row.length, 0, y, row.length, 1);
                            for (int pixel : row) {
                                crc.update(pixel >>> 24);
                                crc.update(pixel >>> 16);
                                crc.update(pixel >>> 8);
                                crc.update(pixel);
                            }
                        }
                        result.put("pixel_crc32", crc.getValue());
                    } catch (Throwable error) {
                        result.put("state", "error").put("error_type", error.getClass().getName()).put("message", String.valueOf(error.getMessage()));
                        JSONArray stack = new JSONArray();
                        for (int i = 0; i < Math.min(8, error.getStackTrace().length); i++)
                            stack.put(error.getStackTrace()[i].toString());
                        result.put("stack", stack);
                    } finally {
                        if (bitmap != null) bitmap.recycle();
                    }
                    result.put("elapsed_ms", (System.nanoTime() - started) / 1_000_000.0);
                    results.put(result);
                }
        }
        System.out.println(new JSONObject().put("scope", "Android ImageDecoder; no Godot/XR/2D-to-3D").put("results", results).toString());
    }
}
