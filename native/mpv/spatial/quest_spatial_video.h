/* Apple MV-HEVC stereo decoding helpers. LGPL-2.1-or-later, like mpv. */
#ifndef QUEST_SPATIAL_VIDEO_H
#define QUEST_SPATIAL_VIDEO_H
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/intreadwrite.h>
#include <libavutil/pixdesc.h>
#include <libavutil/stereo3d.h>
#include <stdbool.h>
#include <string.h>

/* hvcC VPS: vps_max_layers_minus1 follows the first six payload bits.
 * Bounds-check each array/NAL; multilayer alone also includes Dolby Vision. */
static bool quest_spatial_multilayer(const uint8_t *data, int size) {
  if (!data || size < 23 || data[0] != 1)
    return false;
  int offset = 23;
  for (int array = 0; array < data[22]; array++) {
    if (size - offset < 3)
      return false;
    int type = data[offset++] & 63;
    int count = AV_RB16(data + offset);
    offset += 2;
    for (int nal = 0; nal < count; nal++) {
      if (size - offset < 2)
        return false;
      int length = AV_RB16(data + offset);
      offset += 2;
      if (length > size - offset)
        return false;
      if (type == 32 && length >= 4 &&
          (((data[offset + 2] & 3) << 4) | (data[offset + 3] >> 4)))
        return true;
      offset += length;
    }
  }
  return false;
}

static bool quest_spatial_candidate(const AVCodecParameters *par) {
  if (!par || par->codec_id != AV_CODEC_ID_HEVC ||
      !quest_spatial_multilayer(par->extradata, par->extradata_size) ||
      av_packet_side_data_get(par->coded_side_data, par->nb_coded_side_data,
                              AV_PKT_DATA_DOVI_CONF))
    return false;
  if (par->profile == AV_PROFILE_HEVC_MULTIVIEW_MAIN)
    return true;
  const AVPacketSideData *sd = av_packet_side_data_get(
      par->coded_side_data, par->nb_coded_side_data, AV_PKT_DATA_STEREO3D);
  /* vexu identifies separate stereo views; ordinary SBS/TB is already packed.
   */
  if (!sd || sd->size < sizeof(AVStereo3D))
    return false;
  const AVStereo3D *stereo = (const AVStereo3D *)sd->data;
  return stereo->type == AV_STEREO3D_UNSPEC ||
         stereo->type == AV_STEREO3D_FRAMESEQUENCE;
}

struct quest_spatial_pair {
  AVFrame *eye[2];
};

static void quest_spatial_clear(struct quest_spatial_pair *pair) {
  av_frame_free(&pair->eye[0]);
  av_frame_free(&pair->eye[1]);
}

/* Return 0 until a complete pair, 1 with packed pixels in frame, <0 on failure.
 * SEI view positions decide eye order; view 0 is the RIGHT eye in iPhone
 * footage. Never join different PTS, retain one frame per eye, clear on every
 * seek/reset. */
static int quest_spatial_join(struct quest_spatial_pair *pair, AVFrame *frame) {
  AVFrameSideData *sd = av_frame_get_side_data(frame, AV_FRAME_DATA_STEREO3D);
  if (!sd || sd->size < sizeof(AVStereo3D) || frame->pts == AV_NOPTS_VALUE)
    return AVERROR_INVALIDDATA;
  const AVStereo3D *stereo = (const AVStereo3D *)sd->data;
  AVStereo3D metadata = *stereo;
  int eye = stereo->view == AV_STEREO3D_VIEW_LEFT    ? 0
            : stereo->view == AV_STEREO3D_VIEW_RIGHT ? 1
                                                     : -1;
  if (eye < 0)
    return AVERROR_INVALIDDATA;
  av_frame_free(&pair->eye[eye]);
  pair->eye[eye] = av_frame_clone(frame);
  if (!pair->eye[eye])
    return AVERROR(ENOMEM);
  av_frame_unref(frame);
  AVFrame *left = pair->eye[0], *right = pair->eye[1];
  if (!left || !right)
    return 0;
  if (left->pts != right->pts) {
    av_frame_free(&pair->eye[left->pts < right->pts ? 0 : 1]);
    return 0;
  }
  const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(left->format);
  if (!desc ||
      (desc->flags & (AV_PIX_FMT_FLAG_HWACCEL | AV_PIX_FMT_FLAG_PAL)) ||
      left->width != right->width || left->height != right->height ||
      left->format != right->format || left->width <= 0 || left->width > 4096 ||
      left->height <= 0 || left->height > 4320 ||
      (left->width % (1 << desc->log2_chroma_w)) || left->crop_left ||
      left->crop_right || left->crop_top || left->crop_bottom ||
      right->crop_left || right->crop_right || right->crop_top ||
      right->crop_bottom)
    return AVERROR_INVALIDDATA;
  frame->format = left->format;
  frame->width = left->width * 2;
  frame->height = left->height;
  int ret = av_frame_get_buffer(frame, 32);
  if (ret < 0 || (ret = av_frame_copy_props(frame, left)) < 0)
    return ret;
  int offsets[4];
  if ((ret = av_image_fill_linesizes(offsets, left->format, left->width)) < 0)
    return ret;
  uint8_t *right_planes[4] = {0};
  for (int p = 0; p < 4; p++)
    if (frame->data[p])
      right_planes[p] = frame->data[p] + offsets[p];
  av_image_copy(frame->data, frame->linesize, (const uint8_t **)left->data,
                left->linesize, left->format, left->width, left->height);
  av_image_copy(right_planes, frame->linesize, (const uint8_t **)right->data,
                right->linesize, right->format, right->width, right->height);
  av_frame_remove_side_data(frame, AV_FRAME_DATA_VIEW_ID);
  av_frame_remove_side_data(frame, AV_FRAME_DATA_STEREO3D);
  AVStereo3D *packed = av_stereo3d_create_side_data(frame);
  if (!packed)
    return AVERROR(ENOMEM);
  *packed = metadata;
  packed->type = AV_STEREO3D_SIDEBYSIDE;
  packed->view = AV_STEREO3D_VIEW_PACKED;
  packed->flags &= ~AV_STEREO3D_FLAG_INVERT;
  quest_spatial_clear(pair);
  return 1;
}
#endif
