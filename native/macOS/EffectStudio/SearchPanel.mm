#import <AppKit/AppKit.h>
#include "SearchPanel.h"
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
}

@interface ESSearchPanel : NSPanel
@end
@implementation ESSearchPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface ESSearchController : NSObject<NSTextFieldDelegate,NSTableViewDataSource,NSTableViewDelegate,NSWindowDelegate> {
@public
 std::vector<effectstudio_mac::Entry> catalog;
 std::vector<effectstudio::search::Entry> index;
 std::vector<size_t> rows;
 uint64_t generation;
}
@property(nonatomic,strong) ESSearchPanel* panel;
@property(nonatomic,strong) NSSearchField* query;
@property(nonatomic,strong) NSTableView* table;
@property(nonatomic,strong) NSTextField* footer;
- (void)refresh;
- (void)accept;
@end

@implementation ESSearchController
- (instancetype)init {
 if(!(self=[super init]))return nil;
 self.panel=[[ESSearchPanel alloc] initWithContentRect:NSMakeRect(0,0,380,220) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
 self.panel.releasedWhenClosed=NO; self.panel.delegate=self; self.panel.hidesOnDeactivate=YES;
 self.panel.backgroundColor=[NSColor colorWithWhite:0.12 alpha:1]; self.panel.hasShadow=YES;
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationInactive:) name:NSApplicationDidResignActiveNotification object:NSApp];
 self.panel.level=NSFloatingWindowLevel; self.panel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
 self.query=[[NSSearchField alloc] initWithFrame:NSMakeRect(8,184,364,28)];
 self.query.placeholderString=@"Search effects"; self.query.delegate=self;
 self.query.sendsSearchStringImmediately=YES; self.query.accessibilityLabel=@"Search effects";
 [self.panel.contentView addSubview:self.query];
 NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(4,28,372,150)];
 scroll.hasVerticalScroller=YES; scroll.drawsBackground=NO;
 self.table=[[NSTableView alloc] initWithFrame:scroll.bounds]; self.table.headerView=nil;
 self.table.backgroundColor=self.panel.backgroundColor; self.table.rowHeight=25;
 self.table.dataSource=self; self.table.delegate=self; self.table.target=self; self.table.action=@selector(accept);
 NSTableColumn* name=[[NSTableColumn alloc] initWithIdentifier:@"effect"]; name.width=350; [self.table addTableColumn:name];
 scroll.documentView=self.table; [self.panel.contentView addSubview:scroll];
 self.footer=[NSTextField labelWithString:@""]; self.footer.frame=NSMakeRect(10,5,360,18);
 self.footer.font=[NSFont systemFontOfSize:11]; self.footer.textColor=[NSColor secondaryLabelColor];
 [self.panel.contentView addSubview:self.footer]; return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { return (NSInteger)rows.size(); }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
 if(row<0||(size_t)row>=rows.size())return nil;
 NSTextField* cell=[NSTextField labelWithString:String(catalog[rows[row]].name)];
 cell.font=[NSFont systemFontOfSize:13]; cell.lineBreakMode=NSLineBreakByTruncatingTail;
 cell.toolTip=[NSString stringWithFormat:@"%@ — %@",String(catalog[rows[row]].name),String(catalog[rows[row]].category)];return cell;
}
- (void)refresh {
 rows.clear(); auto query=Wide(self.query.stringValue);
 if(query.empty()){for(size_t i=0;i<catalog.size()&&rows.size()<6;++i)rows.push_back(i);}
 else for(const auto& hit:effectstudio::search::Find(index,query,6))rows.push_back(hit.index);
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
- (void)accept {
 if(!NSApp.active||pending)return;
 NSInteger row=self.table.selectedRow;if(row<0||(size_t)row>=rows.size())return;
 pending=effectstudio_mac::Choice{catalog[rows[row]].id,generation};
 [self.panel orderOut:nil];
}
- (void)windowDidResignKey:(NSNotification*)notification { [self.panel orderOut:nil]; }
- (void)applicationInactive:(NSNotification*)notification { pending.reset();[self.panel orderOut:nil]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

namespace { ESSearchController* controller; }
namespace effectstudio_mac {
bool OpenSearch(const std::vector<Entry>& entries,unsigned count,std::uint64_t stamp){
 if(!NSThread.isMainThread||!NSApp.active)return false;
 if(!controller)controller=[ESSearchController new];
 pending.reset();controller->catalog=entries;controller->generation=stamp;controller->index.clear();
 for(size_t i=0;i<entries.size();++i){effectstudio::search::Entry item;item.index=i;item.displayName=Wide(String(entries[i].name));item.names.push_back(effectstudio::search::Prepare(item.displayName));for(auto& alias:entries[i].aliases)item.names.push_back(effectstudio::search::Prepare(Wide(String(alias))));controller->index.push_back(std::move(item));}
 controller.query.stringValue=@"";controller.footer.stringValue=[NSString stringWithFormat:@"%u selected · Return apply · Esc close",count];[controller refresh];
 NSPoint pointer=NSEvent.mouseLocation;NSScreen* screen=NSScreen.mainScreen;
 for(NSScreen* candidate in NSScreen.screens)if(NSPointInRect(pointer,candidate.frame)){screen=candidate;break;}
 if(!screen)return false;NSRect area=screen.visibleFrame,frame=controller.panel.frame;
 frame.origin.x=MAX(NSMinX(area),MIN(pointer.x,NSMaxX(area)-frame.size.width));
 frame.origin.y=MAX(NSMinY(area),MIN(pointer.y-frame.size.height,NSMaxY(area)-frame.size.height));
 [controller.panel setFrame:frame display:NO];[controller.panel makeKeyAndOrderFront:nil];[controller.panel makeFirstResponder:controller.query];return true;
}
bool TakeChoice(Choice& choice){if(!NSThread.isMainThread||!pending)return false;if(!NSApp.active){pending.reset();return false;}choice=*pending;pending.reset();return true;}
void CloseSearch(){if(!NSThread.isMainThread)return;[controller.panel orderOut:nil];pending.reset();}
void Shutdown(){CloseSearch();controller.panel.delegate=nil;[controller.panel close];controller=nil;}
bool IsOpen(){return NSThread.isMainThread&&controller.panel.visible;}
}
