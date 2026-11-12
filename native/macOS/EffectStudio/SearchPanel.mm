#import <AppKit/AppKit.h>
#include "SearchPanel.h"
#include "Preferences.h"
#include "../../EffectStudio/EffectStudioSearch.h"
#include <optional>
#include <cstring>

namespace {
NSString* String(const std::wstring& value) {
 return [[NSString alloc] initWithBytes:value.data() length:value.size()*sizeof(wchar_t) encoding:NSUTF32LittleEndianStringEncoding] ?: @"";
}
std::wstring Wide(NSString* value) {
 // Foundation provides invariant Unicode decomposition/case conversion on Mac.
 NSString* normalized=[[value decomposedStringWithCanonicalMapping] lowercaseStringWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
 NSData* data=[normalized dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
 std::wstring result(data.length/sizeof(wchar_t), L'\0');
 if(data.length)memcpy(result.data(),data.bytes,data.length);
 return result;
}
std::optional<effectstudio_mac::Choice> pending;
std::optional<std::pair<effectstudio_mac::HostAction,std::uint64_t>> pendingAction;
}

@interface ESSearchPanel : NSPanel
@end
@implementation ESSearchPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end
@interface ESResultsTable : NSTableView
@end
@implementation ESResultsTable
- (void)keyDown:(NSEvent*)event {if(event.keyCode==36||event.keyCode==76){[NSApp sendAction:@selector(accept) to:self.target from:self];return;}if(event.keyCode==53){[NSApp sendAction:@selector(cancelSearch) to:self.target from:self];return;}[super keyDown:event];}
@end

@interface ESSearchController : NSObject<NSTextFieldDelegate,NSTableViewDataSource,NSTableViewDelegate,NSWindowDelegate> {
@public
 std::vector<effectstudio_mac::Entry> catalog;
 std::vector<effectstudio::search::Entry> index;
 std::vector<size_t> rows;
 std::map<NSInteger,std::wstring> groupRows;
 std::set<std::wstring> closedGroups;
 effectstudio_mac::Preferences prefs;
 bool browsing=false;
 uint64_t generation;
}
@property(nonatomic,strong) ESSearchPanel* panel;
@property(nonatomic,strong) NSSearchField* query;
@property(nonatomic,strong) NSTableView* table;
@property(nonatomic,strong) NSTextField* footer;
@property(nonatomic,strong) NSScrollView* scroll;
@property(nonatomic,strong) NSButton* browserButton;
@property(nonatomic,strong) NSButton* settingsButton;
@property(nonatomic,strong) NSButton* captureButton;
@property(nonatomic,strong) NSButton* saveCaptureButton;
@property(nonatomic,strong) NSPanel* settings;
@property(nonatomic,strong) NSPopUpButton* effectPicker;
@property(nonatomic,strong) NSTextField* aliasField;
@property(nonatomic,strong) NSButton* favoriteCheck;
@property(nonatomic,strong) NSButton* expandedCheck;
@property(nonatomic,strong) NSPopUpButton* shortcutPicker;
@property(nonatomic,strong) NSTextField* settingsStatus;
@property(nonatomic,strong) id keyMonitor;
- (void)refresh;
- (void)accept;
- (void)rowClicked;
- (void)cancelSearch;
- (void)reindex;
- (void)layout;
- (void)toggleBrowser;
- (void)openSettings;
- (void)loadEffect;
- (void)saveSettings;
- (void)centerSettings;
- (void)capture;
- (void)saveCapture;
@end

@implementation ESSearchController
- (instancetype)init {
 if(!(self=[super init]))return nil;
 self.panel=[[ESSearchPanel alloc] initWithContentRect:NSMakeRect(0,0,380,220) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
 self.panel.releasedWhenClosed=NO; self.panel.delegate=self; self.panel.hidesOnDeactivate=YES;
 self.panel.backgroundColor=[NSColor colorWithWhite:0.12 alpha:1]; self.panel.hasShadow=YES;
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationInactive:) name:NSApplicationDidResignActiveNotification object:NSApp];
 self.panel.level=NSFloatingWindowLevel; self.panel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
 self.query=[[NSSearchField alloc] initWithFrame:NSMakeRect(8,184,294,28)];
 self.query.placeholderString=@"Search effects"; self.query.delegate=self;
 self.query.sendsSearchStringImmediately=YES; self.query.accessibilityLabel=@"Search effects";
 [self.panel.contentView addSubview:self.query];
 NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(4,28,372,150)];
 self.scroll=scroll;
 scroll.hasVerticalScroller=YES; scroll.drawsBackground=NO;
 self.table=[[ESResultsTable alloc] initWithFrame:scroll.bounds]; self.table.headerView=nil;
 self.table.backgroundColor=self.panel.backgroundColor; self.table.rowHeight=25;
 self.table.dataSource=self; self.table.delegate=self; self.table.target=self; self.table.action=@selector(rowClicked);self.table.doubleAction=@selector(accept);
 NSTableColumn* name=[[NSTableColumn alloc] initWithIdentifier:@"effect"]; name.width=350; [self.table addTableColumn:name];
 scroll.documentView=self.table; [self.panel.contentView addSubview:scroll];
 self.footer=[NSTextField labelWithString:@""]; self.footer.frame=NSMakeRect(10,5,360,18);
 self.footer.font=[NSFont systemFontOfSize:11]; self.footer.textColor=[NSColor secondaryLabelColor];
 [self.panel.contentView addSubview:self.footer];
 self.browserButton=[NSButton buttonWithTitle:@"☷" target:self action:@selector(toggleBrowser)];self.browserButton.toolTip=@"Toggle category browser";
 self.settingsButton=[NSButton buttonWithTitle:@"⚙" target:self action:@selector(openSettings)];self.settingsButton.toolTip=@"Favorites, aliases and shortcuts";
 [self.panel.contentView addSubview:self.browserButton];[self.panel.contentView addSubview:self.settingsButton];
 self.captureButton=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"camera" accessibilityDescription:@"Copy composition snapshot"] target:self action:@selector(capture)];self.captureButton.toolTip=@"Copy composition snapshot";[self.panel.contentView addSubview:self.captureButton];
 self.saveCaptureButton=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"square.and.arrow.down" accessibilityDescription:@"Save last snapshot"] target:self action:@selector(saveCapture)];self.saveCaptureButton.toolTip=@"Choose destination and save last snapshot";[self.panel.contentView addSubview:self.saveCaptureButton];
 std::string error;if(!prefs.Load(error))self.footer.stringValue=[NSString stringWithUTF8String:error.c_str()];
 __weak ESSearchController* weak=self;
 self.keyMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent*(NSEvent* event){
  ESSearchController* strong=weak;if(!strong||!NSApp.active||NSApp.modalWindow||NSApp.keyWindow.sheetParent)return event;
  id responder=NSApp.keyWindow.firstResponder;if([responder isKindOfClass:NSTextView.class]&&[(NSTextView*)responder hasMarkedText])return event;
  if(event.keyCode==53){if(strong.settings.visible&&NSApp.keyWindow==strong.settings){[strong.settings orderOut:nil];return nil;}if(strong->browsing&&strong.panel.visible){pending.reset();pendingAction.reset();[strong.panel orderOut:nil];return nil;}return event;}
  if(strong.panel.visible&&!strong.settings.keyWindow&&(event.modifierFlags&NSEventModifierFlagOption)&&!(event.modifierFlags&(NSEventModifierFlagCommand|NSEventModifierFlagControl))){
   NSString* chars=event.charactersIgnoringModifiers;if(chars.length==1){unichar c=[chars characterAtIndex:0];if(c>='1'&&c<='9'&&!pending&&!pendingAction){const auto& id=strong->prefs.shortcuts[c-'1'];if(!id.empty()){pending=effectstudio_mac::Choice{id,strong->generation};if(!strong->browsing)[strong.panel orderOut:nil];return nil;}}}
  }return event;
 }];
 [self layout];return self;
}
- (void)layout {NSRect r=self.panel.contentView.bounds;self.query.frame=NSMakeRect(8,r.size.height-36,r.size.width-144,28);self.captureButton.frame=NSMakeRect(r.size.width-132,r.size.height-35,28,26);self.saveCaptureButton.frame=NSMakeRect(r.size.width-100,r.size.height-35,28,26);self.browserButton.frame=NSMakeRect(r.size.width-68,r.size.height-35,28,26);self.settingsButton.frame=NSMakeRect(r.size.width-36,r.size.height-35,28,26);self.scroll.frame=NSMakeRect(4,28,r.size.width-8,MAX(25,r.size.height-70));self.footer.frame=NSMakeRect(10,5,r.size.width-20,18);self.table.tableColumns.firstObject.width=r.size.width-24;}
- (void)windowDidResize:(NSNotification*)notification {if(notification.object==self.panel)[self layout];}
- (void)reindex {index.clear();for(size_t i=0;i<catalog.size();++i){effectstudio::search::Entry item;item.index=i;item.displayName=Wide(String(catalog[i].name));item.names.push_back(effectstudio::search::Prepare(item.displayName));for(auto& alias:catalog[i].aliases)item.names.push_back(effectstudio::search::Prepare(Wide(String(alias))));auto custom=prefs.aliases.find(catalog[i].id);if(custom!=prefs.aliases.end()&&!custom->second.empty()){item.shortcutAlias=effectstudio::search::Normalize(Wide(String(custom->second)));item.names.push_back(effectstudio::search::Prepare(item.shortcutAlias));}item.favorite=prefs.favorites.count(catalog[i].id)>0;index.push_back(std::move(item));}}
- (void)toggleBrowser {browsing=!browsing;NSRect frame=self.panel.frame;NSPoint top=NSMakePoint(NSMinX(frame),NSMaxY(frame));self.panel.styleMask=browsing?(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable):NSWindowStyleMaskBorderless;self.panel.title=@"Effect Studio";self.panel.minSize=NSMakeSize(380,browsing?250:220);if(browsing){if(![self.panel setFrameUsingName:@"EffectStudio.Browser.Frame"]){[self.panel setContentSize:NSMakeSize(500,600)];} [self.panel setFrameAutosaveName:@"EffectStudio.Browser.Frame"];}else{[self.panel setFrameAutosaveName:@""];[self.panel setContentSize:NSMakeSize(380,220)];[self.panel setFrameTopLeftPoint:top];}[self layout];[self refresh];}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { return (NSInteger)rows.size(); }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
 if(row<0||(size_t)row>=rows.size())return nil;
 auto group=groupRows.find(row);if(group!=groupRows.end()){NSTextField* cell=[NSTextField labelWithString:[NSString stringWithFormat:@"%@ %@",closedGroups.count(group->second)?@"▸":@"▾",String(group->second)]];cell.font=[NSFont boldSystemFontOfSize:12];return cell;}
 NSTextField* cell=[NSTextField labelWithString:String(catalog[rows[row]].name)];
 if(prefs.favorites.count(catalog[rows[row]].id))cell.stringValue=[@"★ " stringByAppendingString:cell.stringValue];
 cell.font=[NSFont systemFontOfSize:13]; cell.lineBreakMode=NSLineBreakByTruncatingTail;
 cell.toolTip=[NSString stringWithFormat:@"%@ — %@",String(catalog[rows[row]].name),String(catalog[rows[row]].category)];return cell;
}
- (void)refresh {
 rows.clear();groupRows.clear(); auto query=Wide(self.query.stringValue);
 if(query.empty()&&browsing){std::map<std::wstring,std::vector<size_t>> groups;for(size_t i=0;i<catalog.size();++i)groups[catalog[i].category.empty()?L"Other":catalog[i].category].push_back(i);for(auto&group:groups){groupRows[(NSInteger)rows.size()]=group.first;rows.push_back(SIZE_MAX);if(!closedGroups.count(group.first))rows.insert(rows.end(),group.second.begin(),group.second.end());}}
 else if(query.empty()){for(size_t i=0;i<catalog.size()&&rows.size()<6;++i)if(prefs.favorites.count(catalog[i].id))rows.push_back(i);}
 else for(const auto& hit:effectstudio::search::Find(index,query,browsing?catalog.size():6))rows.push_back(hit.index);
 [self.table reloadData]; if(!rows.empty())[self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}
- (void)controlTextDidChange:(NSNotification*)notification { [self refresh]; }
- (BOOL)control:(NSControl*)control textView:(NSTextView*)editor doCommandBySelector:(SEL)command {
 // Let Cocoa's input method consume marked text before command acceptance.
 if(editor.hasMarkedText)return NO;
 if(command==@selector(insertNewline:)){[self accept];return YES;}
 if(command==@selector(cancelOperation:)){[self.panel orderOut:nil];return YES;}
 if(command==@selector(moveDown:)||command==@selector(moveUp:)){
  if(rows.empty())return YES;
  NSInteger row=self.table.selectedRow+(command==@selector(moveDown:)?1:-1);
  row=MAX(0,MIN(row,(NSInteger)rows.size()-1));
  [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];[self.table scrollRowToVisible:row];return YES;
 }return NO;
}
- (void)rowClicked {if(!browsing||groupRows.count(self.table.selectedRow))[self accept];}
- (void)cancelSearch {pending.reset();pendingAction.reset();[self.panel orderOut:nil];}
- (void)accept {
 if(!NSApp.active||pending||pendingAction)return;
 NSInteger row=self.table.selectedRow;if(row<0||(size_t)row>=rows.size())return;
 auto group=groupRows.find(row);if(group!=groupRows.end()){if(closedGroups.count(group->second))closedGroups.erase(group->second);else closedGroups.insert(group->second);[self refresh];return;}
 pending=effectstudio_mac::Choice{catalog[rows[row]].id,generation};
 if(!browsing)[self.panel orderOut:nil];
}
- (void)windowDidResignKey:(NSNotification*)notification { if(notification.object==self.panel&&!browsing&&!self.settings.visible)[self.panel orderOut:nil]; }
- (void)applicationInactive:(NSNotification*)notification { pending.reset();pendingAction.reset();if(!browsing)[self.panel orderOut:nil]; }
- (void)capture {if(!pending&&!pendingAction&&NSApp.active){pendingAction=std::make_pair(effectstudio_mac::HostAction::Capture,generation);if(!browsing)[self.panel orderOut:nil];}}
- (void)saveCapture {if(!pending&&!pendingAction&&NSApp.active){pendingAction=std::make_pair(effectstudio_mac::HostAction::SaveCapture,generation);if(!browsing)[self.panel orderOut:nil];}}
- (void)openSettings {
 pending.reset();pendingAction.reset();
 if(!self.settings){
  self.settings=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,480,340) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];self.settings.title=@"Effect Studio Settings";self.settings.releasedWhenClosed=NO;self.settings.hidesOnDeactivate=YES;self.settings.level=NSFloatingWindowLevel;self.settings.appearance=self.panel.appearance;
  if(![self.settings setFrameUsingName:@"EffectStudio.Settings.Frame"])[self.settings center];[self.settings setFrameAutosaveName:@"EffectStudio.Settings.Frame"];
  self.effectPicker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(18,286,444,28) pullsDown:NO];self.effectPicker.target=self;self.effectPicker.action=@selector(loadEffect);[self.settings.contentView addSubview:self.effectPicker];
  NSTextField* aliasLabel=[NSTextField labelWithString:@"Search alias"];aliasLabel.frame=NSMakeRect(20,251,200,20);[self.settings.contentView addSubview:aliasLabel];
  self.aliasField=[[NSTextField alloc] initWithFrame:NSMakeRect(20,218,440,26)];self.aliasField.placeholderString=@"Optional search name";[self.settings.contentView addSubview:self.aliasField];
  self.favoriteCheck=[NSButton checkboxWithTitle:@"Favorite (also shown when compact search is empty)" target:nil action:nil];self.favoriteCheck.frame=NSMakeRect(20,180,440,24);[self.settings.contentView addSubview:self.favoriteCheck];
  self.shortcutPicker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(20,140,220,28) pullsDown:NO];[self.shortcutPicker addItemWithTitle:@"No quick shortcut"];for(int i=1;i<=9;++i)[self.shortcutPicker addItemWithTitle:[NSString stringWithFormat:@"Option + %d",i]];[self.settings.contentView addSubview:self.shortcutPicker];
  self.expandedCheck=[NSButton checkboxWithTitle:@"Open in expanded view" target:nil action:nil];self.expandedCheck.frame=NSMakeRect(20,104,300,24);[self.settings.contentView addSubview:self.expandedCheck];
  NSButton* save=[NSButton buttonWithTitle:@"Save" target:self action:@selector(saveSettings)];save.frame=NSMakeRect(350,58,110,30);[self.settings.contentView addSubview:save];
  NSButton* center=[NSButton buttonWithTitle:@"Center settings" target:self action:@selector(centerSettings)];center.frame=NSMakeRect(20,58,150,30);[self.settings.contentView addSubview:center];
  self.settingsStatus=[NSTextField labelWithString:@"Option shortcuts work while search is open."];self.settingsStatus.frame=NSMakeRect(20,10,440,38);self.settingsStatus.lineBreakMode=NSLineBreakByWordWrapping;self.settingsStatus.maximumNumberOfLines=2;[self.settings.contentView addSubview:self.settingsStatus];
 }
 [self.effectPicker removeAllItems];for(const auto& entry:catalog)[self.effectPicker addItemWithTitle:String(entry.name)];
 NSInteger row=self.table.selectedRow;if(row>=0&&(size_t)row<rows.size()&&rows[row]!=SIZE_MAX)[self.effectPicker selectItemAtIndex:rows[row]];
 [self loadEffect];self.expandedCheck.state=prefs.expanded?NSControlStateValueOn:NSControlStateValueOff;[self.settings makeKeyAndOrderFront:nil];
}
- (void)loadEffect {NSInteger selected=self.effectPicker.indexOfSelectedItem;if(selected<0||(size_t)selected>=catalog.size())return;const auto&id=catalog[selected].id;auto alias=prefs.aliases.find(id);self.aliasField.stringValue=alias==prefs.aliases.end()?@"":String(alias->second);self.favoriteCheck.state=prefs.favorites.count(id)?NSControlStateValueOn:NSControlStateValueOff;[self.shortcutPicker selectItemAtIndex:0];for(size_t i=0;i<9;++i)if(prefs.shortcuts[i]==id)[self.shortcutPicker selectItemAtIndex:i+1];}
- (void)saveSettings {NSInteger selected=self.effectPicker.indexOfSelectedItem;if(selected<0||(size_t)selected>=catalog.size())return;auto next=prefs;const auto&id=catalog[selected].id;std::wstring alias=Wide(self.aliasField.stringValue);if(alias.size()>240){self.settingsStatus.stringValue=@"Keep aliases within 240 characters.";return;}if(alias.empty())next.aliases.erase(id);else next.aliases[id]=alias;if(self.favoriteCheck.state==NSControlStateValueOn)next.favorites.insert(id);else next.favorites.erase(id);for(auto&shortcut:next.shortcuts)if(shortcut==id)shortcut.clear();NSInteger shortcut=self.shortcutPicker.indexOfSelectedItem;if(shortcut>0&&shortcut<=9)next.shortcuts[shortcut-1]=id;next.expanded=self.expandedCheck.state==NSControlStateValueOn;std::string error;if(!next.Save(error)){self.settingsStatus.stringValue=[NSString stringWithUTF8String:error.c_str()];return;}prefs=std::move(next);[self reindex];[self refresh];self.settingsStatus.stringValue=@"Saved. Launcher keys remain controlled by After Effects.";}
- (void)centerSettings {[NSWindow removeFrameUsingName:@"EffectStudio.Settings.Frame"];[self.settings center];[self.settings saveFrameUsingName:@"EffectStudio.Settings.Frame"];}
- (void)dealloc {if(self.keyMonitor)[NSEvent removeMonitor:self.keyMonitor];[[NSNotificationCenter defaultCenter] removeObserver:self];}
@end

namespace { ESSearchController* controller; }
namespace effectstudio_mac {
bool OpenSearch(const std::vector<Entry>& entries,unsigned count,std::uint64_t stamp){
 if(!NSThread.isMainThread||!NSApp.active)return false;
 if(!controller)controller=[ESSearchController new];
 pending.reset();pendingAction.reset();controller->catalog=entries;controller->generation=stamp;controller->index.clear();
 [controller reindex];if(controller->browsing!=controller->prefs.expanded)[controller toggleBrowser];
 controller.query.stringValue=@"";controller.footer.stringValue=[NSString stringWithFormat:@"%u selected · Return apply · Esc close",count];[controller refresh];
 NSPoint pointer=NSEvent.mouseLocation;NSScreen* screen=NSScreen.mainScreen;
 for(NSScreen* candidate in NSScreen.screens)if(NSPointInRect(pointer,candidate.frame)){screen=candidate;break;}
 if(!screen)return false;NSRect area=screen.visibleFrame,frame=controller.panel.frame;
 frame.origin.x=MAX(NSMinX(area),MIN(pointer.x,NSMaxX(area)-frame.size.width));
 frame.origin.y=MAX(NSMinY(area),MIN(pointer.y-frame.size.height,NSMaxY(area)-frame.size.height));
 [controller.panel setFrame:frame display:NO];[controller.panel makeKeyAndOrderFront:nil];[controller.panel makeFirstResponder:controller.query];return true;
}
bool TakeChoice(Choice& choice){if(!NSThread.isMainThread||!pending)return false;if(!NSApp.active){pending.reset();return false;}choice=*pending;pending.reset();return true;}
bool TakeHostAction(HostAction& action,std::uint64_t& stamp){if(!NSThread.isMainThread||!pendingAction)return false;if(!NSApp.active){pendingAction.reset();return false;}action=pendingAction->first;stamp=pendingAction->second;pendingAction.reset();return true;}
void CloseSearch(){if(!NSThread.isMainThread)return;[controller.panel orderOut:nil];pending.reset();pendingAction.reset();}
void Shutdown(){CloseSearch();controller.panel.delegate=nil;[controller.settings close];[controller.panel close];controller=nil;}
bool IsOpen(){return NSThread.isMainThread&&controller.panel.visible;}
bool IsBrowserOpen(){return IsOpen()&&controller->browsing;}
void UpdateSelection(unsigned count,std::uint64_t stamp){if(!NSThread.isMainThread||!controller)return;controller->generation=stamp;controller.footer.stringValue=[NSString stringWithFormat:@"%u selected · Return apply · Esc close",count];}
}
