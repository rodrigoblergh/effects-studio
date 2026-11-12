// Included inside the private host namespace. Adobe calls remain on its idle thread.
void CaptureSnapshot(State& s,bool save){
 if(!NSApp.active||s.dying)return;
 std::string destination;
 if(save){destination=effectstudio_mac::ChooseSnapshotPath("Composition.png");if(destination.empty()||s.dying)return;}
 if(save&&!s.lastCapture.rgba.empty()){effectstudio_mac::SaveSnapshot(s.lastCapture,destination);return;}
 API api(s.basic);AEGP_ItemH active=nullptr;A_long id=0;AEGP_ItemType type=AEGP_ItemType_NONE;
 Check(api.item->AEGP_GetActiveItem(&active));
 if(!active||active!=s.snapshot.item)throw std::runtime_error("Composition changed. Open Effect Studio again.");
 Check(api.item->AEGP_GetItemID(active,&id));Check(api.item->AEGP_GetItemType(active,&type));
 if(id!=s.snapshot.itemId||type!=AEGP_ItemType_COMP)throw std::runtime_error("Open a composition before taking a snapshot.");
 Suite<AEGP_RenderOptionsSuite4> options(s.basic,kAEGPRenderOptionsSuite,kAEGPRenderOptionsSuiteVersion4);
 Suite<AEGP_RenderSuite5> render(s.basic,kAEGPRenderSuite,kAEGPRenderSuiteVersion5);
 Suite<AEGP_WorldSuite3> world(s.basic,kAEGPWorldSuite,kAEGPWorldSuiteVersion3);
 AEGP_RenderOptionsH settings=nullptr;AEGP_FrameReceiptH receipt=nullptr;
 effectstudio_mac::SnapshotImage image;
 try{
  Check(options->AEGP_NewFromItem(s.plugin,active,&settings));A_Time time{};
  Check(api.item->AEGP_GetItemCurrentTime(active,&time));Check(options->AEGP_SetTime(settings,time));
  Check(options->AEGP_SetWorldType(settings,AEGP_WorldType_8));Check(options->AEGP_SetDownsampleFactor(settings,1,1));
  Check(options->AEGP_SetMatteMode(settings,AEGP_MatteMode_PREMUL_BG_COLOR));Check(options->AEGP_SetChannelOrder(settings,AEGP_ChannelOrder_ARGB));
  A_LRect roi{};Check(options->AEGP_SetRegionOfInterest(settings,&roi));
  Check(render->AEGP_RenderAndCheckoutFrame(settings,nullptr,nullptr,&receipt));
  AEGP_WorldH pixels=nullptr;Check(render->AEGP_GetReceiptWorld(receipt,&pixels));
  A_long width=0,height=0;A_u_long stride=0;PF_Pixel8* base=nullptr;
  Check(world->AEGP_GetSize(pixels,&width,&height));Check(world->AEGP_GetRowBytes(pixels,&stride));Check(world->AEGP_GetBaseAddr8(pixels,&base));
  image=effectstudio_mac::OpaqueSnapshot(reinterpret_cast<const unsigned char*>(base),width,height,stride);
  auto oldReceipt=receipt;receipt=nullptr;Check(render->AEGP_CheckinFrame(oldReceipt));
  auto oldSettings=settings;settings=nullptr;Check(options->AEGP_Dispose(oldSettings));
 }catch(...){if(receipt)render->AEGP_CheckinFrame(receipt);if(settings)options->AEGP_Dispose(settings);throw;}
 if(s.dying)return;
 if(save)effectstudio_mac::SaveSnapshot(image,destination);else effectstudio_mac::CopySnapshot(image);
 s.lastCapture=std::move(image);
}
