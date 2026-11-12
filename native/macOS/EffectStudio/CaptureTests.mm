#import <AppKit/AppKit.h>
#include "CaptureSupport.h"
#include <cassert>
#include <iostream>
int main(){@autoreleasepool{
 unsigned char input[]={0,12,34,56,128,78,90,123,99,99,99,99,255,200,150,100,0,1,2,3,99,99,99,99};
 auto image=effectstudio_mac::OpaqueSnapshot(input,2,2,12);
 assert((image.rgba==std::vector<unsigned char>{12,34,56,255,78,90,123,255,200,150,100,255,1,2,3,255}));
 auto png=effectstudio_mac::EncodeSnapshotPNG(image);assert(png.size()>8&&png[0]==137&&png[1]=='P');
 NSBitmapImageRep* decoded=[NSBitmapImageRep imageRepWithData:[NSData dataWithBytes:png.data() length:png.size()]];
 assert(decoded.pixelsWide==2&&decoded.pixelsHigh==2);
 NSUInteger pixel[4]={};[decoded getPixel:pixel atX:0 y:0];assert(pixel[0]==12&&pixel[1]==34&&pixel[2]==56);
 bool rejected=false;try{effectstudio_mac::OpaqueSnapshot(input,2,2,7);}catch(...){rejected=true;}assert(rejected);
 rejected=false;try{effectstudio_mac::OpaqueSnapshot(input,32768,32768,131072);}catch(...){rejected=true;}assert(rejected);
 std::cout<<"PASS opaque composition background, ARGB conversion, stride, PNG roundtrip and allocation limits. Clipboard untouched.\n";
}}
