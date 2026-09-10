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
)
