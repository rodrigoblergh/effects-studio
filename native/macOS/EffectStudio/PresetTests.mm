#import <Foundation/Foundation.h>
#include "Presets.h"
#include <iostream>
#include <stdexcept>
void Check(bool value,const char* message){if(!value)throw std::runtime_error(message);}
int main(){@autoreleasepool{
 NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"effect-preset-test-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
 NSFileManager* fm=NSFileManager.defaultManager;
 try{
  NSURL* nested=[root URLByAppendingPathComponent:@"Unicode Ç" isDirectory:YES];Check([fm createDirectoryAtURL:nested withIntermediateDirectories:YES attributes:nil error:nil],"Create fixture");
  NSURL* preset=[nested URLByAppendingPathComponent:@"Example.ffx"];Check([[@"fixture" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:preset atomically:YES],"Write fixture");
  Check([fm createSymbolicLinkAtURL:[nested URLByAppendingPathComponent:@"cycle"] withDestinationURL:root error:nil],"Create cycle");
  auto first=effectstudio_mac::presets::Scan({root.fileSystemRepresentation,root.fileSystemRepresentation});Check(first.entries.size()==1&&!first.incomplete,"Nested/cycle/duplicate scan");auto id=first.entries[0].id;Check(effectstudio_mac::presets::IsPreset(first.entries[0].presetPath),"Existing preset");
  auto again=effectstudio_mac::presets::Scan({root.fileSystemRepresentation});Check(again.entries[0].id==id,"Stable canonical ID");
  auto escaped=effectstudio_mac::presets::JSString(L"/tmp/\"quote\n\U0001F680.ffx");Check(escaped.find("\\ud83d\\ude80")!=std::string::npos&&escaped.find("\\u000a")!=std::string::npos,"UTF32 to ExtendScript UTF16 escaping");
  auto script=effectstudio_mac::presets::ApplyScript(12,{1,3},L"/tmp/example.ffx");Check(script.find("c.id!==12")!=std::string::npos&&script.find("targets[0].applyPreset(f)")!=std::string::npos&&script.find("finally{")!=std::string::npos,"Single native preset call and selection restoration");
  Check([fm removeItemAtURL:preset error:nil],"Remove fixturepreset");Check(effectstudio_mac::presets::Scan({root.fileSystemRepresentation}).entries.empty(),"Fresh rescan omits removedpreset");
  [fm removeItemAtURL:root error:nil];std::cout<<"PASS preset traversal/cycle/Unicode/stableID/rescan/script guards; no AE actions.\n";return 0;
 }catch(const std::exception&e){[fm removeItemAtURL:root error:nil];std::cerr<<e.what()<<'\n';return 1;}
}}
