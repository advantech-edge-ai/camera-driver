#!/bin/bash
# internet_list.sh - camera drivers published on the public internet
# (GitHub: https://github.com/advantech-edge-ai/camera-driver/releases).
#
# Sourced by online_mode.sh.  Do not run directly.
#
#   INTERNET_PROBE   URL tested to decide whether GitHub is reachable
#   INTERNET_LIST    key = <vendor>/<sensor>/<platform>/<board>/<jetpack>
#                    val = release-asset download URL
#
# Only the releases that currently exist on GitHub are listed. When a new
# release is published, add one line here (and, for offline use, mirror the
# asset onto the internal server and add it to internal_list.sh).

# HTML repo page (always answers a HEAD; a release-asset URL 302-redirects to a
# host that can reject HEAD, so probe the repo page, not an asset).
INTERNET_PROBE="https://github.com/advantech-edge-ai/camera-driver"

declare -gA INTERNET_LIST=(
  ["otobrite/imx728/agx_orin/mic_733ao/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/otobrite-imx728-mic_733ao_jetpack_6.2_v1.0.0-v2/MIC-733AO_Orin_6.2_V1.0.0_Otobrite_IMX728_V2.tbz2"
  ["otobrite/isx031/agx_orin/mic_733ao/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/otobrite-isx031-mic_733ao_jetpack_6.2_v1.0.0-v2/MIC-733AO_Orin_6.2_V1.0.0_Otobrite_ISX031_V2.tbz2"
  ["sensing/universal/agx_orin/mic_733ao/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/sensing-universal-mic-733_agx_orin_jetpack_6.2_v1.0.0-v1/MIC-AGX-Orin_JP6.2_Sensing_Universal_YUV_GMSL2x4_MAX9296A_V1.0.0.zip"
  ["econ/STURDeCAM31/agx_orin/mic_733ao/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/econ-cam31-mic-733ao-jp6.2_v1.0.0-v1/MIC-733AO_32G_Orin_6.2_v1.0.0_Econ_Cam31_V1.tbz2"
  ["otobrite/imx728/agx_orin/mic_732/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/otobrite-imx728-mic_732_64g_jetpack_6.2_v1.0.2-v1/MIC-732_64G_Orin_6.2_V1.0.2_Otobrite_IMX728_V1.tbz2"
  ["otobrite/isx031/agx_orin/mic_732/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/otobrite-isx031-mic_732_64g_jetpack_6.2_v1.0.2-v1/MIC-732_64G_Orin_6.2_V1.0.2_OTOBRITE_ISX031_V1.tbz2"
  ["otobrite/imx728/orin_nx_orin_nano/mic_711/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/otobrite-imx728-mic_711_jetpack_6.2_v1.0.0-v1/MIC-711_Orin_6.2_V1.0.0_Otobrite_IMX728_V1.tbz2"
  ["otobrite/isx031/orin_nx_orin_nano/mic_711/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/otobrite-isx031-mic_711_jetpack_6.2_v1.0.0-v1/MIC-711_Orin_6.2_V1.0.0_Otobrite_ISX031_V1.tbz2"
  ["sensing/universal/orin_nx_orin_nano/mic_713/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/sensing-universal-mic-713_orin_nx_jetpack_6.2_v1.0.0-v1/MIC_Orin_NX_JP6.2_Sensing_Universal_V1.0.0.zip"
  ["sensing/universal/orin_nx_orin_nano/mic_712/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/sensing-universal-mic-712ar_orin_nx_jetpack_6.2_v1.0.0-v1/MIC-712AR_Orin_NX_JP6.2_Sensing_Universal_V1.0.0.zip"
  ["econ/STURDeCAM25/agx_orin/mic_733ao/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/econ-cam25-mic-733ao_jp6.2_v1.0.0-v1/MIC-733AO_32G_Orin_6.2_v1.0.0_Econ_Cam25_V1.tbz2"
  ["econ/STURDeCAM25/orin_nx_orin_nano/mic_713/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/econ-cam25-mic-713_jp6.2_v1.0.1-v1/MIC-713_OrinNX_6.2.0_v1.0.1_Econ_Cam25_V1.tbz2"
  ["econ/STURDeCAM31/orin_nx_orin_nano/mic_713/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/econ-cam31-mic-713_jp6.2_v1.0.1-v1/MIC-713_OrinNX_6.2.0_v1.0.1_Econ_Cam31_V1.tbz2"
  ["stereolabs/ZED_X/agx_orin/mic_733ao/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/stereolabs-mic733ao_jetpack6.2_v1-v1/MIC-733AO_JP6.x_MAX9296_ZEDX_driver_Package.tbz2"
  ["stereolabs/ZED_X/orin_nx_orin_nano/mic_713/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/stereolabs-mic713_jetpack6.2_v1-v1/MIC-713_JP6.2_MAX9296_ZEDX_driver_Package.tbz2"
  ["orbbec/gl335i/agx_orin/mic_732/jp6.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/orbbec-gl335l-mic_732_64g_jetpack_6.2_v1.0.2-v3/AI_MIC-732_64G_Orin_6.2_V1.0.2_Orbbec_G335GL_V3.tbz2"
  ["sensing/universal/thor/mic_741/jp7.1"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/sensing-universal-mic-741_sensing_yuv_gmsl2x8_jetpack_7.1_v1.1.2-v1/MIC-741_Sensing_YUV_GMSL2x8_JP7.1_V1.1.2.zip"
  ["sensing/universal/thor/mic_741/jp7.0"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/sensing-universal-mic_741_t5000_jetpack_7.0_v1.0.0-v1/MIC-741_T5000_jp7.0_Sensing_Universal_V1.0.0.zip"
  ["sensing/common/thor/mic_741/jp7.0"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/sensing-common-mic_741_t5000_jetpack_7.0_v1.0.0-v1/MIC-741_Thor_7.0_V1.0.0_Sensing_ISX031C_Octa_V1.zip"
  ["sensing/isx031/thor/mic_743/jp7.0"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/sensing-isx031-mic_743_t5000_jetpakc_7.0_v1.0.4-v1/MIC-743_Thor_7.0_V1.0.4_Sensing_ISX031_V1.tbz2"
  ["stereolabs/ZED_X/thor/mic_743/jp7.1"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/stereolabs-mic743_jetpack7.1_v1-v1/MIC-743_JP7.1_MAX96712_ZEDX_install_package.tbz2"
  ["econ/STURDeCAM25/thor/mic_742/jp7.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/econ-cam25-mic-742-jp7.2_v1.0.0-v1/MIC-742_THOR_7.2.0_v1.0.0_Econ_Cam25_V1.tbz2"
  ["econ/STURDeCAM31/thor/mic_742/jp7.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/econ-cam31-mic-742-jp7.2_v1.0.0-v1/MIC-742_THOR_7.2.0_v1.0.0_Econ_Cam31_V1.tbz2"
  ["econ/STURDeCAM25/thor/mic_743/jp7.1"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/econ-cam25-mic-743-jp7.1_v1-v1/STURDeCAM25_CUTAGX_JETSON_AGX_THOR_L4T38.2.0_25-MAR-2026_R01_RC1.tar.gz"
  ["econ/STURDeCAM31/thor/mic_743/jp7.0"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/econ-cam31-mic-743-jp7.0_v1-v1/STURDeCAM31_CUTAGX_CXLC_AT_JETSON_L4T38.2.0_30-JAN-2026_R01_RC1.tar.gz"
  ["realsense/D457/thor/mic_742/jp7.0"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/realsense-mic_742_jetpack_7.0_v1.0.0-v2/AI_MIC-742_Thor_7.0_V1.0.0_Realsense_D457_V2.tbz2"
  ["realsense/D457/thor/mic_742/jp7.2"]="https://github.com/advantech-edge-ai/camera-driver/releases/download/realsense-mic_742_jetpack_7.2_v1.0.0-v1/AI_MIC-742_Thor_7.2_V1.0.0_Realsense_D457_V1.tbz2"
)
