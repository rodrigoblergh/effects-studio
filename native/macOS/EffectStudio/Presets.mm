#import <Foundation/Foundation.h>
#include "Presets.h"
#include <sys/stat.h>
#include <set>
#include <algorithm>
#include <cstring>
#include <stdexcept>
namespace effectstudio_mac { namespace presets {namespace {
std::wstring Wide(NSString* text){NSData* data=[text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];std::wstring out(data.length/4,L'\0');if(data.length)memcpy(out.data(),data.bytes,data.length);return out;}
NSString* Text(const std::wstring& s){return [[NSString alloc] initWithBytes:s.data() length:s.size()*4 encoding:NSUTF32LittleEndianStringEncoding];}
NSURL* Resolve(NSURL* file){NSNumber* alias=nil;NSError* error=nil;if(![file getResourceValue:&alias forKey:NSURLIsAliasFileKey error:&error])return nil;if(alias.boolValue){file=[NSURL URLByResolvingAliasFileAtURL:file options:NSURLBookmarkResolutionWithoutUI|NSURLBookmarkResolutionWithoutMounting error:&error];if(!file)return nil;}return file.URLByResolvingSymlinksInPath.URLByStandardizingPath;}
}
std::vector<std::string> Roots(){@autoreleasepool{
 NSMutableArray<NSURL*>* candidates=[NSMutableArray array];NSURL* app=NSBundle.mainBundle.bundleURL;
 if(app){[candidates addObject:[app.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Presets" isDirectory:YES]];[candidates addObject:[app URLByAppendingPathComponent:@"Contents/Resources/Presets" isDirectory:YES]];}
 NSURL* docs=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
 NSURL* adobe=[docs URLByAppendingPathComponent:@"Adobe" isDirectory:YES];
 NSArray<NSURL*>* products=[NSFileManager.defaultManager contentsOfDirectoryAtURL:adobe includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
 for(NSURL* product in products)if([product.lastPathComponent hasPrefix:@"After Effects"]){[candidates addObject:[product URLByAppendingPathComponent:@"User Presets" isDirectory:YES]];[candidates addObject:[product URLByAppendingPathComponent:@"Presets" isDirectory:YES]];}
 [candidates addObject:[adobe URLByAppendingPathComponent:@"User Presets" isDirectory:YES]];
 std::vector<std::string> roots;for(NSURL* url in candidates)if(url.fileSystemRepresentation)roots.emplace_back(url.fileSystemRepresentation);return roots;
}}
Result Scan(const std::vector<std::string>& roots){@autoreleasepool{
 Result out;std::set<std::pair<dev_t,ino_t>> visited;std::vector<std::pair<std::string,unsigned>> pending;for(auto& root:roots)pending.push_back({root,0});size_t files=0;CFAbsoluteTime started=CFAbsoluteTimeGetCurrent();
 while(!pending.empty()){@autoreleasepool{
  if(visited.size()>=12000||files>=30000||CFAbsoluteTimeGetCurrent()-started>3){out.incomplete=true;break;}
  auto next=pending.back();pending.pop_back();if(next.second>64){out.incomplete=true;continue;}
  NSString* source=[[NSString alloc] initWithUTF8String:next.first.c_str()];if(!source){out.incomplete=true;continue;}NSURL* url=Resolve([NSURL fileURLWithPath:source]);if(!url)continue;
  struct stat info{};if(stat(url.fileSystemRepresentation,&info)!=0)continue;if(!visited.insert({info.st_dev,info.st_ino}).second)continue;
  if(S_ISDIR(info.st_mode)){NSError* error=nil;NSArray<NSURL*>* children=[NSFileManager.defaultManager contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[NSURLIsAliasFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];if(!children){out.incomplete=true;continue;}for(NSURL* child in children){if(pending.size()>=30000){out.incomplete=true;break;}if(child.fileSystemRepresentation)pending.push_back({child.fileSystemRepresentation,next.second+1});}continue;}
  ++files;if(!S_ISREG(info.st_mode)||[url.pathExtension caseInsensitiveCompare:@"ffx"]!=NSOrderedSame)continue;
  Entry entry;entry.presetPath=Wide(url.path);entry.id="preset:"+std::string(url.fileSystemRepresentation);entry.name=Wide(url.lastPathComponent.stringByDeletingPathExtension);entry.category=L"Presets / "+Wide(url.URLByDeletingLastPathComponent.lastPathComponent);out.entries.push_back(std::move(entry));
 }}
 std::sort(out.entries.begin(),out.entries.end(),[](const Entry&a,const Entry&b){return a.id<b.id;});return out;
}}
bool IsPreset(const std::wstring& path){@autoreleasepool{NSString* text=Text(path);if(!text||[text.pathExtension caseInsensitiveCompare:@"ffx"]!=NSOrderedSame)return false;struct stat info{};return stat(text.fileSystemRepresentation,&info)==0&&S_ISREG(info.st_mode);}}
std::string JSString(const std::wstring& value){const char* hex="0123456789abcdef";std::string out="\"";auto unit=[&](unsigned code){out+="\\u";for(int shift=12;shift>=0;shift-=4)out+=hex[(code>>shift)&15];};for(wchar_t c:value){unsigned code=static_cast<unsigned>(c);if(code>0x10ffff||(code>=0xd800&&code<=0xdfff))throw std::runtime_error("Invalid preset path Unicode");if(code>0xffff){code-=0x10000;unit(0xd800+(code>>10));unit(0xdc00+(code&1023));}else unit(code);}return out+"\"";}
std::string ApplyScript(long compId,const std::vector<long>& indices,const std::wstring& path){if(indices.empty()||compId<=0||path.empty())throw std::runtime_error("Invalid preset targets");std::string ids="[";for(size_t i=0;i<indices.size();++i){if(indices[i]<1)throw std::runtime_error("Invalid layer index");if(i)ids+=",";ids+=std::to_string(indices[i]);}ids+="]";
 return "(function(){var c=app.project.activeItem;if(!(c instanceof CompItem)||c.id!=="+std::to_string(compId)+")throw Error('Composition changed');var f=new File("+JSString(path)+");if(!f.exists)throw Error('Preset file is missing');var ids="+ids+",targets=[],old=c.selectedLayers;for(var i=0;i<ids.length;i++){var l=c.layer(ids[i]);if(!l||l.locked)throw Error('Target layer changed');targets.push(l);}try{for(var j=0;j<old.length;j++)old[j].selected=false;for(var k=0;k<targets.length;k++)targets[k].selected=true;targets[0].applyPreset(f);}finally{var now=c.selectedLayers;for(var n=0;n<now.length;n++)now[n].selected=false;for(var m=0;m<old.length;m++)if(isValid(old[m]))old[m].selected=true;}return 'ok';})()";
}
}}
