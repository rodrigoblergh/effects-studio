#import <Foundation/Foundation.h>
#include "Preferences.h"
#include <cstring>
namespace effectstudio_mac { namespace {
NSURL* File(){NSURL* support=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;return [[support URLByAppendingPathComponent:@"Effect Studio" isDirectory:YES] URLByAppendingPathComponent:@"preferences.json"];}
NSString* Text(const std::string&s){return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding]?:@"";}
std::wstring Wide(NSString*s){NSData*d=[s dataUsingEncoding:NSUTF32LittleEndianStringEncoding];std::wstring out(d.length/4,L'\0');if(d.length)memcpy(out.data(),d.bytes,d.length);return out;}
}
bool Preferences::Load(std::string& error){@autoreleasepool{
 NSURL* file=File();if(![NSFileManager.defaultManager fileExistsAtPath:file.path])return true;
 NSError* problem=nil;NSData* data=[NSData dataWithContentsOfURL:file options:0 error:&problem];
 if(!data||data.length>1048576){error="Preferences could not be read or exceed 1MB.";return false;}
 id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:&problem];
 if(![root isKindOfClass:NSDictionary.class]||![root[@"schema"] isEqual:@1]){error="Unsupported preferences format.";return false;}
 Preferences next;
 id fav=root[@"favorites"],aliases=root[@"aliases"],shortcuts=root[@"shortcuts"];
 if(![fav isKindOfClass:NSArray.class]||![aliases isKindOfClass:NSDictionary.class]||![shortcuts isKindOfClass:NSArray.class]||[shortcuts count]!=9){error="Invalid preferences values.";return false;}
 for(id value in fav){if(![value isKindOfClass:NSString.class]){error="Invalid favorite.";return false;}next.favorites.insert([value UTF8String]);}
 for(id key in aliases){id value=aliases[key];if(![key isKindOfClass:NSString.class]||![value isKindOfClass:NSString.class]){error="Invalid alias.";return false;}next.aliases[[key UTF8String]]=Wide(value);}
 for(NSUInteger i=0;i<9;++i){id value=shortcuts[i];if(![value isKindOfClass:NSString.class]){error="Invalid shortcut.";return false;}next.shortcuts[i]=[value UTF8String];}
 id expanded=root[@"expanded"];if(expanded&&CFGetTypeID((__bridge CFTypeRef)expanded)!=CFBooleanGetTypeID()){error="Invalid startup view.";return false;}next.expanded=[expanded boolValue];*this=std::move(next);return true;
}}
bool Preferences::Save(std::string& error)const{@autoreleasepool{
 NSMutableArray* fav=[NSMutableArray array],*keys=[NSMutableArray array];NSMutableDictionary* names=[NSMutableDictionary dictionary];
 for(auto&s:favorites)[fav addObject:Text(s)];for(auto&s:shortcuts)[keys addObject:Text(s)];
 for(auto&item:aliases){NSString* value=[[NSString alloc] initWithBytes:item.second.data() length:item.second.size()*4 encoding:NSUTF32LittleEndianStringEncoding];names[Text(item.first)]=value?:@"";}
 NSDictionary* root=@{@"schema":@1,@"favorites":fav,@"aliases":names,@"shortcuts":keys,@"expanded":@(expanded)};
 NSError* problem=nil;NSData* data=[NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&problem];NSURL* file=File();
 if(!data||![NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&problem]||![data writeToURL:file options:NSDataWritingAtomic error:&problem]){error=problem.localizedDescription.UTF8String?:"Preferences could not be saved.";return false;}return true;
}}
}
