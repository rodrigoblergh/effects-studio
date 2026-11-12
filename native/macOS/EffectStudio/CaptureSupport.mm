#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "CaptureSupport.h"
#include <stdexcept>
#include <cstring>

namespace effectstudio_mac {
static void Validate(const SnapshotImage& image){
 if(image.width<=0||image.height<=0||image.width>32768||image.height>32768||
  static_cast<unsigned long long>(image.width)*image.height>67108864ULL||
  image.rgba.size()!=static_cast<std::size_t>(image.width)*image.height*4)
  throw std::runtime_error("Invalid composition snapshot.");
}
SnapshotImage OpaqueSnapshot(const unsigned char* source,int width,int height,std::size_t stride){
 if(!source||width<=0||height<=0||width>32768||height>32768||
  static_cast<unsigned long long>(width)*height>67108864ULL||stride<static_cast<std::size_t>(width)*4)
  throw std::runtime_error("Invalid rendered composition pixels.");
 SnapshotImage image;image.width=width;image.height=height;image.rgba.resize(static_cast<std::size_t>(width)*height*4);
 for(int y=0;y<height;++y)for(int x=0;x<width;++x){
  const unsigned char* pixel=source+static_cast<std::size_t>(y)*stride+x*4;
  auto offset=(static_cast<std::size_t>(y)*width+x)*4;
  // RGB already contains AE's composition background. Do not composite twice.
  image.rgba[offset]=pixel[1];image.rgba[offset+1]=pixel[2];image.rgba[offset+2]=pixel[3];image.rgba[offset+3]=255;
 }
 return image;
}
std::vector<unsigned char> EncodeSnapshotPNG(const SnapshotImage& image){
 Validate(image);
 @autoreleasepool {
  NSBitmapImageRep* rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:image.width pixelsHigh:image.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:NSBitmapFormatAlphaNonpremultiplied bytesPerRow:image.width*4 bitsPerPixel:32];
  if(!rep||!rep.bitmapData)throw std::runtime_error("Cannot allocate composition snapshot.");
  memcpy(rep.bitmapData,image.rgba.data(),image.rgba.size());
  NSData* png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  if(!png.length)throw std::runtime_error("Cannot encode composition PNG.");
  auto begin=static_cast<const unsigned char*>(png.bytes);return std::vector<unsigned char>(begin,begin+png.length);
 }
}
void CopySnapshot(const SnapshotImage& image){
 if(![NSThread isMainThread])throw std::runtime_error("Clipboard access must run on the host UI thread.");
 auto png=EncodeSnapshotPNG(image);NSData* bytes=[NSData dataWithBytes:png.data() length:png.size()];
 NSPasteboardItem* item=[[NSPasteboardItem alloc] init];
 if(![item setData:bytes forType:NSPasteboardTypePNG])throw std::runtime_error("Cannot prepare clipboard image.");
 NSPasteboard* pasteboard=[NSPasteboard generalPasteboard];[pasteboard clearContents];
 if(![pasteboard writeObjects:@[item]])throw std::runtime_error("The clipboard could not accept the snapshot.");
}
std::string ChooseSnapshotPath(const std::string& suggested){
 if(![NSThread isMainThread])throw std::runtime_error("Save dialog must run on the host UI thread.");
 NSSavePanel* panel=[NSSavePanel savePanel];panel.title=@"Save composition snapshot";
 panel.allowedContentTypes=@[UTTypePNG];panel.canCreateDirectories=YES;
 NSString* name=[[NSString alloc] initWithBytes:suggested.data() length:suggested.size() encoding:NSUTF8StringEncoding];
 panel.nameFieldStringValue=name.length?name:@"Composition.png";
 if([panel runModal]!=NSModalResponseOK)return {};
 return panel.URL.fileSystemRepresentation?:"";
}
void SaveSnapshot(const SnapshotImage& image,const std::string& path){
 if(path.empty())throw std::runtime_error("Choose an export filename.");
 auto png=EncodeSnapshotPNG(image);NSData* bytes=[NSData dataWithBytes:png.data() length:png.size()];
 NSURL* destination=[NSURL fileURLWithFileSystemRepresentation:path.c_str() isDirectory:NO relativeToURL:nil];
 NSError* error=nil;if(![bytes writeToURL:destination options:NSDataWritingAtomic error:&error])
  throw std::runtime_error(error.localizedDescription.UTF8String?:"Could not save the PNG.");
}
}
