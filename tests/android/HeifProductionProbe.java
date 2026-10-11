package org.vrpassthroughplayer.probe;

import java.io.File;
import java.io.FileInputStream;
import java.security.MessageDigest;
import java.util.zip.CRC32;
import kotlin.Unit;
import org.json.JSONArray;
import org.json.JSONObject;
import org.vrpassthroughplayer.plugin.HeifPhotoDecoder;
import org.vrpassthroughplayer.plugin.HeifPhotoInfo;

/** Calls the actual production parser and bitmap/raw handoff on a device, without an APK or XR. */
public final class HeifProductionProbe {
    private static String hash(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[65536]; int count;
            while ((count = input.read(buffer)) >= 0) digest.update(buffer,0,count);
        }
        StringBuilder text = new StringBuilder();
        for (byte value : digest.digest()) text.append(String.format("%02x", value & 255));
        return text.toString();
    }
    public static void main(String[] args) throws Exception {
        File output = new File(args[0]); output.mkdirs();
        JSONArray results = new JSONArray();
        for (int index=1; index<args.length; index++) {
            File source = new File(args[index]);
            JSONObject result = new JSONObject().put("file",source.getName());
            long started=System.nanoTime();
            try {
                String original=hash(source);
                HeifPhotoInfo info=HeifPhotoInfo.Companion.read(source);
                if (info==null) throw new IllegalStateException("Not a supported HEIF");
                File directory=new File(output,"sample-"+index); directory.mkdirs();
                JSONObject ready=HeifPhotoDecoder.INSTANCE.prepare(source,directory,info,()->Unit.INSTANCE,metadata->Unit.INSTANCE);
                int width=ready.getInt("decoded_width"), height=ready.getInt("decoded_height");
                File pixels=new File(ready.getString("path"));
                if (pixels.length()!=(long)width*height*4) throw new IllegalStateException("Raw payload size mismatch");
                CRC32 left=new CRC32(), right=new CRC32();
                try (FileInputStream input=new FileInputStream(pixels)) {
                    byte[] row=new byte[width*4];
                    for (int y=0;y<height;y++) {
                        int count=0;
                        while(count<row.length) { int n=input.read(row,count,row.length-count); if(n<0) throw new IllegalStateException("Short row"); count+=n; }
                        int eyeBytes=info.getStereo()?row.length/2:row.length;
                        left.update(row,0,eyeBytes);
                        if(info.getStereo()) right.update(row,eyeBytes,eyeBytes);
                    }
                }
                boolean unchanged=original.equals(hash(source));
                if(!unchanged || (info.getStereo() && left.getValue()==right.getValue())) throw new IllegalStateException("Source mutated or identical eyes");
                result.put("state","ready").put("native_stereo",info.getStereo()).put("width",width).put("height",height)
                    .put("left_crc32",left.getValue()).put("right_crc32",right.getValue()).put("source_unchanged",unchanged)
                    .put("thumbnail_present",new File(ready.getString("thumbnail_path")).isFile());
            } catch(Throwable error) {
                result.put("state","error").put("error_type",error.getClass().getName()).put("message",String.valueOf(error.getMessage()));
                JSONArray stack=new JSONArray();
                for(int i=0;i<Math.min(8,error.getStackTrace().length);i++) stack.put(error.getStackTrace()[i].toString());
                result.put("stack",stack);
            }
            result.put("elapsed_ms",(System.nanoTime()-started)/1_000_000.0); results.put(result);
        }
        System.out.println(new JSONObject().put("scope","Production HEIF parser and raw/thumbnail output; no Godot/XR/depth model").put("results",results));
    }
}
