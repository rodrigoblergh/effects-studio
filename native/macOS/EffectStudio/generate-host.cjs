// One-time source scaffolding from our own Windows host's portable SDK routines.
// Does not modify Windows sources and does not copy Adobe SDK sources.
const fs=require('fs'),path=require('path');
const source=fs.readFileSync(path.join(__dirname,'../../EffectStudio/EffectStudioHost.cpp'),'utf8');
const section=(start,end)=>source.slice(source.indexOf(start),source.indexOf(end));
const preamble=`#import <AppKit/AppKit.h>
#include "AEConfig.h"
#include "AE_GeneralPlug.h"
#include "SearchPanel.h"
#include "Aliases.h"
#include <algorithm>
#include <map>
#include <memory>
#include <stdexcept>
#include <cstring>
#include <type_traits>
namespace {
`;
const state=`struct State {
 SPBasicSuite* basic=nullptr;AEGP_PluginID plugin=0;AEGP_Command command=0;
 bool ready=false,dying=false;unsigned depth=0;std::uint64_t generation=0;
 Snapshot snapshot;std::vector<effectstudio_mac::Entry> catalog;
 std::map<std::string,AEGP_InstalledEffectKey> effectKeys;
};
struct Callback {State* state;explicit Callback(State* s):state(s){++state->depth;}~Callback(){if(--state->depth==0&&state->dying)delete state;}};
`;
const portable=section('void Check(A_Err error)','bool HostHasForeground()');
const helpers=section('struct Collection {','std::wstring Wide(const char* text)');
const tail=`
std::wstring Wide(const char* input){NSString* text=input?[[NSString alloc] initWithUTF8String:input]:@"";if(!text)return {};NSData* data=[text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];std::wstring result(data.length/4,L'\\0');if(data.length)memcpy(result.data(),data.bytes,data.length);return result;}
void Catalog(State&s,API&api){if(!s.catalog.empty())return;A_long count=0;Check(api.effect->AEGP_GetNumInstalledEffects(&count));AEGP_InstalledEffectKey key=AEGP_InstalledEffectKey_NONE;
 for(A_long i=0;i<count;++i){AEGP_InstalledEffectKey next=AEGP_InstalledEffectKey_NONE;Check(api.effect->AEGP_GetNextInstalledEffect(key,&next));if(next==key||next==AEGP_InstalledEffectKey_NONE)break;key=next;
 char name[AEGP_MAX_EFFECT_NAME_SIZE]={},match[AEGP_MAX_EFFECT_MATCH_NAME_SIZE]={},category[AEGP_MAX_EFFECT_CATEGORY_NAME_SIZE]={};Check(api.effect->AEGP_GetEffectName(key,name));Check(api.effect->AEGP_GetEffectMatchName(key,match));Check(api.effect->AEGP_GetEffectCategory(key,category));
 if(!*match||!*name||category[0]=='_'||s.effectKeys.count(match))continue;s.catalog.push_back({match,Wide(name),Wide(category),{}});s.effectKeys.emplace(match,key);
 }effectstudio_mac::AddCatalogAliases(s.catalog);
}
void Apply(State&s,const effectstudio_mac::Choice& choice){
 if(!NSApp.active||choice.generation!=s.generation)return;
 API api(s.basic);Snapshot current;AEGP_CompH comp=nullptr;bool compatible=false;
 if(!Selection(s,api,current,comp,compatible)||s.dying||current.item!=s.snapshot.item||current.itemId!=s.snapshot.itemId||current.ids!=s.snapshot.ids){if(!s.dying)Report(s,"Selection changed. Open Effect Studio again; nothing was applied.");return;}
 auto found=s.effectKeys.find(choice.id);if(found==s.effectKeys.end())throw std::runtime_error("Effect unavailable");
 std::vector<AEGP_LayerH> targets;unsigned skipped=0,failed=0,applied=0;
 for(auto id:current.ids){AEGP_LayerH layer=nullptr;Check(api.layer->AEGP_GetLayerFromLayerID(comp,id,&layer));if(!layer)throw std::runtime_error("Layer disappeared");if(Compatible(api,layer))targets.push_back(layer);else ++skipped;}
 if(s.dying)return;if(targets.empty()){Report(s,"No unlocked compatible layers selected.");return;}
 {Undo undo(api);{Quiet quiet(api);for(auto layer:targets){if(s.dying)break;EffectRef effect(api);if(api.effect->AEGP_ApplyEffect(s.plugin,layer,found->second,&effect.handle)==A_Err_NONE&&effect.handle)++applied;else ++failed;}}undo.End();}
 if(!s.dying&&(skipped||failed)){std::string report="Applied to "+std::to_string(applied)+" layer(s); skipped "+std::to_string(skipped)+", failed "+std::to_string(failed)+". Undo once to restore applied changes.";Report(s,report.c_str());}
}
A_Err Command(AEGP_GlobalRefcon global,AEGP_CommandRefcon,AEGP_Command command,AEGP_HookPriority,A_Boolean,A_Boolean* handled){auto*s=reinterpret_cast<State*>(global);if(!s||s->dying||!s->ready||command!=s->command)return A_Err_NONE;Callback scope(s);if(handled)*handled=TRUE;
 try{if(effectstudio_mac::IsOpen()){effectstudio_mac::CloseSearch();return A_Err_NONE;}API api(s->basic);Snapshot snapshot;AEGP_CompH comp=nullptr;bool compatible=false;
 if(!Selection(*s,api,snapshot,comp,compatible)||!compatible){if(!s->dying)Report(*s,"Select unlocked visual layers in a composition first.");return A_Err_NONE;}
 Catalog(*s,api);if(s->dying)return A_Err_NONE;s->snapshot=std::move(snapshot);++s->generation;
 if(!effectstudio_mac::OpenSearch(s->catalog,(unsigned)s->snapshot.ids.size(),s->generation))Report(*s,"Effect Studio search could not open.");
 }catch(...){if(!s->dying)Report(*s,"Effect Studio could not read effects or selection.");}return A_Err_NONE;}
A_Err Update(AEGP_GlobalRefcon global,AEGP_UpdateMenuRefcon,AEGP_WindowType){auto*s=reinterpret_cast<State*>(global);if(!s||s->dying||!s->ready)return A_Err_NONE;Callback scope(s);try{Suite<AEGP_CommandSuite1> commands(s->basic,kAEGPCommandSuite,kAEGPCommandSuiteVersion1);Check(commands->AEGP_EnableCommand(s->command));}catch(...){}return A_Err_NONE;}
A_Err Idle(AEGP_GlobalRefcon global,AEGP_IdleRefcon,A_long* sleep){auto*s=reinterpret_cast<State*>(global);if(sleep)*sleep=1;if(!s||s->dying||!s->ready)return A_Err_NONE;Callback scope(s);effectstudio_mac::Choice choice;if(effectstudio_mac::TakeChoice(choice)){try{Apply(*s,choice);}catch(...){if(!s->dying)Report(*s,"Apply did not finish. Undo once to restore any completed changes.");}}return A_Err_NONE;}
A_Err Death(AEGP_GlobalRefcon global,AEGP_DeathRefcon){auto*s=reinterpret_cast<State*>(global);if(!s)return A_Err_NONE;s->dying=true;s->ready=false;effectstudio_mac::Shutdown();if(!s->depth)delete s;return A_Err_NONE;}
}
extern "C" __attribute__((visibility("default"))) A_Err EntryPointFunc(SPBasicSuite* basic,A_long,A_long,AEGP_PluginID plugin,AEGP_GlobalRefcon* global){if(!basic||!global)return A_Err_GENERIC;*global=nullptr;
 try{std::unique_ptr<State> owned(new State);owned->basic=basic;owned->plugin=plugin;API api(basic);Suite<AEGP_CommandSuite1> commands(basic,kAEGPCommandSuite,kAEGPCommandSuiteVersion1);Suite<AEGP_RegisterSuite5> registration(basic,kAEGPRegisterSuite,kAEGPRegisterSuiteVersion5);Check(commands->AEGP_GetUniqueCommand(&owned->command));Check(registration->AEGP_RegisterDeathHook(plugin,Death,nullptr));State*s=owned.release();*global=reinterpret_cast<AEGP_GlobalRefcon>(s);
 Check(registration->AEGP_RegisterCommandHook(plugin,AEGP_HP_BeforeAE,s->command,Command,nullptr));Check(registration->AEGP_RegisterUpdateMenuHook(plugin,Update,nullptr));Check(registration->AEGP_RegisterIdleHook(plugin,Idle,nullptr));Check(commands->AEGP_InsertMenuCommand(s->command,"Effect Studio Search (Mac preview)",AEGP_Menu_WINDOW,AEGP_MENU_INSERT_SORTED));s->ready=true;return A_Err_NONE;
 }catch(A_Err error){return error;}catch(...){return A_Err_GENERIC;}}
static_assert(std::is_same<decltype(&EntryPointFunc),AEGP_PluginInitFunc>::value,"AEGP entrypoint ABI mismatch");
`;
fs.writeFileSync(path.join(__dirname,'NativeHost.mm'),preamble+portable+state+helpers+tail);
const aliases=fs.readFileSync(path.join(__dirname,'../../EffectStudio/EffectStudioAliases.h'),'utf8')
 .replace('#include "EffectStudioUI.h"','#include "SearchPanel.h"')
 .replace('namespace effectstudio {','namespace effectstudio_mac {')
 .replace('std::vector<EffectEntry>','std::vector<Entry>')
 .replaceAll('entry.matchName','entry.id');
fs.writeFileSync(path.join(__dirname,'Aliases.h'),aliases);
