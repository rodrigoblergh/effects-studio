#pragma once
#include <cstddef>
#include <string>
#include <vector>
namespace effectstudio_mac {
struct SnapshotImage { int width=0,height=0; std::vector<unsigned char> rgba; };
// SDK input must be AEGP_MatteMode_PREMUL_BG_COLOR / AEGP_ChannelOrder_ARGB.
SnapshotImage OpaqueSnapshot(const unsigned char* argb,int width,int height,std::size_t rowBytes);
std::vector<unsigned char> EncodeSnapshotPNG(const SnapshotImage& image);
void CopySnapshot(const SnapshotImage& image);
// Empty result means cancellation. Call before rendering a new image.
std::string ChooseSnapshotPath(const std::string& suggestedName);
void SaveSnapshot(const SnapshotImage& image,const std::string& path);
}
