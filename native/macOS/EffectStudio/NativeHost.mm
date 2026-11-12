#import <AppKit/AppKit.h>
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
void Check(A_Err error) { if (error != A_Err_NONE) throw error; }
template<class T> class Suite {
    SPBasicSuite* basic_; const char* name_; A_long version_; const T* value_ = nullptr;
public:
    Suite(SPBasicSuite* basic, const char* name, A_long version)
        : basic_(basic), name_(name), version_(version) {
        Check(basic_->AcquireSuite(name_, version_, reinterpret_cast<const void**>(&value_)));
        if (!value_) throw std::runtime_error("Adobe suite unavailable");
    }
    ~Suite() { if (value_) basic_->ReleaseSuite(name_, version_); }
    const T* operator->() const { return value_; }
    Suite(const Suite&) = delete; Suite& operator=(const Suite&) = delete;
};
struct API {
    Suite<AEGP_ItemSuite9> item;
    Suite<AEGP_CompSuite11> comp;
    Suite<AEGP_LayerSuite8> layer;
    Suite<AEGP_CollectionSuite2> collection;
    Suite<AEGP_EffectSuite4> effect;
    Suite<AEGP_UtilitySuite6> utility;
    Suite<AEGP_StreamSuite6> stream;
    Suite<AEGP_DynamicStreamSuite4> dynamic;
    explicit API(SPBasicSuite* b)
        : item(b,kAEGPItemSuite,kAEGPItemSuiteVersion9),
          comp(b,kAEGPCompSuite,kAEGPCompSuiteVersion11),
          layer(b,kAEGPLayerSuite,kAEGPLayerSuiteVersion8),
          collection(b,kAEGPCollectionSuite,kAEGPCollectionSuiteVersion2),
          effect(b,kAEGPEffectSuite,kAEGPEffectSuiteVersion4),
          utility(b,kAEGPUtilitySuite,kAEGPUtilitySuiteVersion6),
          stream(b,kAEGPStreamSuite,kAEGPStreamSuiteVersion6),
          dynamic(b,kAEGPDynamicStreamSuite,kAEGPDynamicStreamSuiteVersion4) {}
};
struct Snapshot {
    AEGP_ItemH item = nullptr; A_long itemId = 0;
    std::vector<AEGP_LayerIDVal> ids;
};
struct State {
 SPBasicSuite* basic=nullptr;AEGP_PluginID plugin=0;AEGP_Command command=0;
 bool ready=false,dying=false;unsigned depth=0;std::uint64_t generation=0;
 Snapshot snapshot;std::vector<effectstudio_mac::Entry> catalog;
 std::map<std::string,AEGP_InstalledEffectKey> effectKeys;
};
struct Callback {State* state;explicit Callback(State* s):state(s){++state->depth;}~Callback(){if(--state->depth==0&&state->dying)delete state;}};
struct Collection {
    API& api; AEGP_Collection2H handle = nullptr;
    explicit Collection(API& a) : api(a) {}
    ~Collection() { if(handle) api.collection->AEGP_DisposeCollection(handle); }
};
struct EffectRef {
    API& api; AEGP_EffectRefH handle = nullptr;
    explicit EffectRef(API& a) : api(a) {}
    ~EffectRef() { if(handle) api.effect->AEGP_DisposeEffect(handle); }
};
struct StreamRef {
    API& api; AEGP_StreamRefH handle=nullptr;
    explicit StreamRef(API& a):api(a) {}
    ~StreamRef(){ if(handle) api.stream->AEGP_DisposeStream(handle); }
};
struct Undo {
    API& api; bool open = false;
    explicit Undo(API& a) : api(a) { Check(api.utility->AEGP_StartUndoGroup("Effect Studio: Apply effect")); open=true; }
    void End() { if(open) { open=false; Check(api.utility->AEGP_EndUndoGroup()); } }
    ~Undo() { if(open) api.utility->AEGP_EndUndoGroup(); }
};
struct Quiet {
    API& api; AEGP_ErrReportState state{}; bool open=false;
    explicit Quiet(API& a):api(a) { Check(api.utility->AEGP_StartQuietErrors(&state)); open=true; }
    ~Quiet(){ if(open) api.utility->AEGP_EndQuietErrors(FALSE,&state); }
};
void Report(State& s, const char* message) noexcept {
    try { Suite<AEGP_UtilitySuite6> u(s.basic,kAEGPUtilitySuite,kAEGPUtilitySuiteVersion6); u->AEGP_ReportInfo(s.plugin,message); } catch(...) {}
}
AEGP_LayerH StreamLayer(const AEGP_StreamCollectionItem& item) {
    switch(item.type) {
    case AEGP_StreamCollectionItemType_LAYER: return item.u.layer_stream.layerH;
    case AEGP_StreamCollectionItemType_MASK: return item.u.mask_stream.mask.layerH;
    case AEGP_StreamCollectionItemType_EFFECT: return item.u.effect_stream.effect.layerH;
    default: return nullptr;
    }
}
AEGP_LayerH CollectionLayer(const AEGP_CollectionItemV2& item) {
    switch(item.type) {
    case AEGP_CollectionItemType_LAYER: return item.u.layer.layerH;
    case AEGP_CollectionItemType_MASK: return item.u.mask.layerH;
    case AEGP_CollectionItemType_EFFECT: return item.u.effect.layerH;
    case AEGP_CollectionItemType_STREAM: return StreamLayer(item.u.stream);
    case AEGP_CollectionItemType_KEYFRAME: return StreamLayer(item.u.keyframe.stream_coll);
    case AEGP_CollectionItemType_MASK_VERTEX: return item.u.mask_vertex.mask_sel.layerH;
    default: return nullptr; // STREAMREF union is expressly invalid in SDK.
    }
}
bool Compatible(API& api, AEGP_LayerH layer) {
    AEGP_LayerFlags flags=0; AEGP_ObjectType type=AEGP_ObjectType_NONE;
    Check(api.layer->AEGP_GetLayerFlags(layer,&flags));
    Check(api.layer->AEGP_GetLayerObjectType(layer,&type));
    return !(flags&AEGP_LayerFlag_LOCKED) &&
        (type==AEGP_ObjectType_AV || type==AEGP_ObjectType_TEXT || type==AEGP_ObjectType_VECTOR);
}
AEGP_LayerH ResolveStreamLayer(State& s,API& api,AEGP_CompH comp,AEGP_StreamRefH selected) {
    if(!selected) return nullptr;
    StreamRef root(api);
    Check(api.stream->AEGP_DuplicateStreamRef(s.plugin,selected,&root.handle));
    A_long depth=0; Check(api.dynamic->AEGP_GetStreamDepth(root.handle,&depth));
    if(depth<0 || depth>256) return nullptr;
    while(depth>0) {
        StreamRef parent(api);
        Check(api.dynamic->AEGP_GetNewParentStreamRef(s.plugin,root.handle,&parent.handle));
        A_long parentDepth=0; Check(api.dynamic->AEGP_GetStreamDepth(parent.handle,&parentDepth));
        if(parentDepth>=depth || parentDepth<0) return nullptr;
        std::swap(root.handle,parent.handle); depth=parentDepth;
    }
    int32_t rootId=0; Check(api.stream->AEGP_GetUniqueStreamID(root.handle,&rootId));
    A_long count=0; Check(api.layer->AEGP_GetCompNumLayers(comp,&count));
    for(A_long i=0;i<count;++i) {
        AEGP_LayerH layer=nullptr; Check(api.layer->AEGP_GetCompLayerByIndex(comp,i,&layer));
        StreamRef candidate(api); Check(api.dynamic->AEGP_GetNewStreamRefForLayer(s.plugin,layer,&candidate.handle));
        int32_t id=0; Check(api.stream->AEGP_GetUniqueStreamID(candidate.handle,&id));
        if(id==rootId) return layer;
    }
    return nullptr;
}
bool Selection(State& s, API& api, Snapshot& result, AEGP_CompH& comp, bool& compatible) {
    compatible=false; comp=nullptr;
    Check(api.item->AEGP_GetActiveItem(&result.item));
    if(!result.item) return false;
    AEGP_ItemType type=AEGP_ItemType_NONE;
    Check(api.item->AEGP_GetItemType(result.item,&type));
    if(type!=AEGP_ItemType_COMP) return false;
    Check(api.item->AEGP_GetItemID(result.item,&result.itemId));
    Check(api.comp->AEGP_GetCompFromItem(result.item,&comp));
    Collection selected(api);
    Check(api.comp->AEGP_GetNewCollectionFromCompSelection(s.plugin,comp,&selected.handle));
    A_u_long count=0; Check(api.collection->AEGP_GetCollectionNumItems(selected.handle,&count));
    for(A_u_long i=0;i<count;++i) {
        AEGP_CollectionItemV2 entry{}; Check(api.collection->AEGP_GetCollectionItemByIndex(selected.handle,i,&entry));
        AEGP_LayerH layer=CollectionLayer(entry);
        if(!layer && entry.type==AEGP_CollectionItemType_STREAMREF)
            layer=ResolveStreamLayer(s,api,comp,entry.stream_refH);
        // Do not silently omit an unresolvable selected item and apply partially.
        if(!layer) return false;
        AEGP_LayerIDVal id=0; Check(api.layer->AEGP_GetLayerID(layer,&id));
        if(std::find(result.ids.begin(),result.ids.end(),id)==result.ids.end()) {
            result.ids.push_back(id); if(Compatible(api,layer)) compatible=true;
        }
    }
    std::sort(result.ids.begin(),result.ids.end());
    return !result.ids.empty();
}

std::wstring Wide(const char* input){NSString* text=input?[[NSString alloc] initWithUTF8String:input]:@"";if(!text)return {};NSData* data=[text dataUsingEncoding:NSUTF32LittleEndianStringEncoding];std::wstring result(data.length/4,L'\0');if(data.length)memcpy(result.data(),data.bytes,data.length);return result;}
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
