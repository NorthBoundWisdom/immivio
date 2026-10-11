package org.vrpassthroughplayer.probe;

import android.content.ContextWrapper;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.File;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import kotlin.Unit;
import org.json.JSONArray;
import org.json.JSONObject;
import org.vrpassthroughplayer.plugin.PhotoPreviewBridge;

/** Exercises the real gallery preview worker using public file samples, without a product Activity. */
public final class HeifPreviewProbe {
    public static void main(String[] args) throws Exception {
        File output=new File(args[0]); output.mkdirs();
        ContextWrapper context=new ContextWrapper(null) { @Override public File getCacheDir() { return output; } };
        JSONArray results=new JSONArray();
        for(int index=1;index<args.length;index++) {
            File source=new File(args[index]);
            JSONObject result=new JSONObject().put("file",source.getName());
            CountDownLatch done=new CountDownLatch(1);
            AtomicReference<String> reply=new AtomicReference<>();
            PhotoPreviewBridge preview=new PhotoPreviewBridge(()->context,uri->uri,uri->Unit.INSTANCE,
                (id,json)->{reply.set(json); done.countDown(); return Unit.INSTANCE;});
            try {
                if(!preview.open(index,"file://"+source.getAbsolutePath())) throw new IllegalStateException("Preview rejected");
                if(!done.await(20,TimeUnit.SECONDS)) throw new IllegalStateException("Preview timed out");
                JSONObject info=new JSONObject(reply.get());
                result.put("state",info.getString("state"));
                if("ready".equals(info.getString("state"))) {
                    Bitmap image=BitmapFactory.decodeFile(info.getString("path"));
                    if(image==null) throw new IllegalStateException("Preview PNG invalid");
                    try {
                        if(Math.max(image.getWidth(),image.getHeight())>512) throw new IllegalStateException("Preview unbounded");
                        result.put("width",image.getWidth()).put("height",image.getHeight()).put("native_stereo",info.optBoolean("native_stereo"))
                            .put("single_eye",info.optBoolean("single_eye"));
                    } finally { image.recycle(); }
                } else result.put("error",info.optString("error"));
            } catch(Throwable error) {
                result.put("state","error").put("error_type",error.getClass().getName()).put("message",String.valueOf(error.getMessage()));
            } finally { preview.close(); }
            results.put(result);
        }
        System.out.println(new JSONObject().put("scope","Production gallery preview; no Godot/XR/depth model").put("results",results));
    }
}
