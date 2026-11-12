#include "../../EffectStudio/EffectStudioSearch.h"
#include "Aliases.h"
#include <iostream>
#include <stdexcept>
void require(bool condition,const char* message){if(!condition)throw std::runtime_error(message);}
int main(){try{
 using namespace effectstudio::search;
 std::vector<effectstudio_mac::Entry> source={{"ADBE Slider Control",L"Slider Control",L"Expression Controls",{}},{"ADBE Gaussian Blur 2",L"Gaussian Blur",L"Blur",{}},{"ADBE Fill",L"Fill",L"Generate",{}}};
 effectstudio_mac::AddCatalogAliases(source);std::vector<Entry> entries;
 for(size_t i=0;i<source.size();++i){Entry item;item.index=i;item.displayName=source[i].name;item.names.push_back(Prepare(item.displayName));for(auto& alias:source[i].aliases)item.names.push_back(Prepare(alias));entries.push_back(item);}
 auto top=[&](const std::wstring&q,size_t wanted){auto hits=Find(entries,q);require(!hits.empty()&&hits.front().index==wanted,"Unexpected top result");};
 top(L"slidr control",0);top(L"Gaussian Blur",1);top(L"desfoque gaussiano",1);top(L"flou gaussien",1);top(L"preenchimento",2);
 require(Normalize(L"gaûssían ^~`' blur")==L"gaussian blur","Accent/punctuation normalization");
 require(Find(entries,L"unrelated xyz123").empty(),"Unrelated search must not invent results");
 std::cout<<"PASS: original search ranking, English, multilingual aliases, typo and punctuation; no AppKit/AE actions.\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
