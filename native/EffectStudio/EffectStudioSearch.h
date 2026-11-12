#pragma once
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <algorithm>
#include <cmath>
#include <cwctype>
#include <map>
#include <set>
#include <string>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#pragma comment(lib,"Normaliz.lib")
#endif
namespace effectstudio { namespace search {
inline std::wstring Normalize(const std::wstring& input){
 std::wstring s=input;
#ifdef _WIN32
 if(!s.empty()){int n=NormalizeString(NormalizationD,s.c_str(),static_cast<int>(s.size()),nullptr,0);if(n>0){std::wstring out(n,L'\0');n=NormalizeString(NormalizationD,s.c_str(),static_cast<int>(s.size()),&out[0],n);if(n>0){out.resize(n);s.swap(out);}}}
 if(!s.empty()){int n=LCMapStringEx(LOCALE_NAME_INVARIANT,LCMAP_LOWERCASE,s.data(),static_cast<int>(s.size()),nullptr,0,nullptr,nullptr,0);if(n>0){std::wstring out(n,L'\0');n=LCMapStringEx(LOCALE_NAME_INVARIANT,LCMAP_LOWERCASE,s.data(),static_cast<int>(s.size()),&out[0],n,nullptr,nullptr,0);if(n>0){out.resize(n);s.swap(out);}}}
#endif
 const std::wstring groups[]={L"àáâãäåāăąÀÁÂÃÄÅĀĂĄ",L"èéêëēĕėęěÈÉÊËĒĔĖĘĚ",L"ìíîïĩīĭįıÌÍÎÏĨĪĬĮ",L"òóôõöøōŏőÒÓÔÕÖØŌŎŐ",L"ùúûüũūŭůűųÙÚÛÜŨŪŬŮŰŲ",L"çćĉċčÇĆĈĊČ",L"ñńņňÑŃŅŇ",L"ýÿŷÝŸŶ",L"śŝşšŚŜŞŠ",L"źżžŹŻŽ",L"ğĝġģĞĜĠĢ",L"łŁ"};
 const std::wstring replacements=L"aeioucnyszgl";
 std::wstring out;bool pendingSpace=false;
 for(wchar_t ch:s){
  if((ch>=0x300&&ch<=0x36f)||std::wstring(L"'’"+std::wstring(1,static_cast<wchar_t>(96))+L"´^~¨").find(ch)!=std::wstring::npos)continue;
  if(iswspace(ch)||std::wstring(L"_-.\\/:()[]").find(ch)!=std::wstring::npos){if(!out.empty())pendingSpace=true;continue;}
  if(pendingSpace){out+=L' ';pendingSpace=false;}
  bool folded=false;for(size_t i=0;i<12;++i)if(groups[i].find(ch)!=std::wstring::npos){out+=replacements[i];folded=true;break;}if(folded)continue;
  if(ch==L'ß'||ch==L'ẞ'){out+=L"ss";continue;}if(ch==L'œ'||ch==L'Œ'){out+=L"oe";continue;}if(ch==L'æ'||ch==L'Æ'){out+=L"ae";continue;}
  out+=static_cast<wchar_t>(towlower(ch));
 }return out;
}
inline std::vector<std::wstring> Words(const std::wstring& s){std::vector<std::wstring> out;size_t start=0;while(start<s.size()){size_t end=s.find(L' ',start);if(end==std::wstring::npos)end=s.size();if(end>start)out.push_back(s.substr(start,end-start));start=end+1;}return out;}
inline int Distance(const std::wstring&a,const std::wstring&b,int limit){
 if(std::abs(static_cast<int>(a.size())-static_cast<int>(b.size()))>limit)return limit+1;
 int inf=limit+1;std::vector<int> prev(b.size()+1,inf),prev2,cur;
 for(size_t j=0;j<=b.size();++j)prev[j]=static_cast<int>(j)<=limit?static_cast<int>(j):inf;
 for(size_t i=1;i<=a.size();++i){cur.assign(b.size()+1,inf);cur[0]=static_cast<int>(i)<=limit?static_cast<int>(i):inf;int lo=std::max(1,static_cast<int>(i)-limit),hi=std::min(static_cast<int>(b.size()),static_cast<int>(i)+limit);for(int j=lo;j<=hi;++j){int v=std::min(cur[j-1]+1,std::min(prev[j]+1,prev[j-1]+(a[i-1]==b[j-1]?0:1)));if(i>1&&j>1&&a[i-1]==b[j-2]&&a[i-2]==b[j-1])v=std::min(v,prev2[j-2]+1);cur[j]=v;}prev2.swap(prev);prev.swap(cur);}return prev[b.size()];
}
struct Name{std::wstring text;std::vector<std::wstring> words;};
inline Name Prepare(const std::wstring&s){Name n;n.text=Normalize(s);n.words=Words(n.text);return n;}
inline double Score(const std::wstring&q,const std::vector<std::wstring>&words,const Name&n,std::map<std::pair<std::wstring,std::wstring>,int>&cache){
 if(q==n.text)return 1000;if(n.text.compare(0,q.size(),q)==0)return 900-q.size()*.01;if(n.text.find(q)!=std::wstring::npos)return 800;
 bool direct=true;double sum=0;for(const auto&part:words){int best=-1;for(const auto&word:n.words){auto key=std::make_pair(part,word);auto found=cache.find(key);int score;if(found!=cache.end())score=found->second;else{if(part==word)score=100;else if(word.compare(0,part.size(),part)==0)score=85;else{int limit=part.size()<3?0:part.size()<7?1:2;int d=Distance(part,word,limit);score=d<=limit?70-d*15:-1;}cache[key]=score;}best=std::max(best,score);if(best==100)break;}if(best<0)return 0;if(best<85)direct=false;sum+=best;}return words.empty()?0:(direct?650:400)+sum/words.size();
}
struct Entry{size_t index;std::wstring displayName;std::vector<Name> names;bool favorite=false;std::wstring shortcutAlias;};
struct Hit{size_t index;double score;bool favorite;bool exactAlias;std::wstring displayName;};
inline std::vector<Hit> Find(const std::vector<Entry>&entries,const std::wstring&query,size_t limit=6){
 std::wstring q=Normalize(query.substr(0,240)).substr(0,120);std::vector<Hit> hits;if(q.empty())return hits;auto words=Words(q);std::map<std::pair<std::wstring,std::wstring>,int> cache;
 for(const auto&entry:entries){double best=0;if(q.size()==1&&q[0]>=L'a'&&q[0]<=L'z'){best=Score(q,words,Prepare(entry.displayName),cache);if(!entry.shortcutAlias.empty())best=std::max(best,Score(q,words,Prepare(entry.shortcutAlias),cache));}else for(const auto&name:entry.names){best=std::max(best,Score(q,words,name,cache));if(best==1000)break;}if(best>0)hits.push_back(Hit{entry.index,best,entry.favorite,!entry.shortcutAlias.empty()&&entry.shortcutAlias==q,entry.displayName});}
 // Explicit aliases win. Literal matches stay above fuzzy suggestions, then
 // favorites lead their group (including ahead of an exact nonfavorite).
 std::stable_sort(hits.begin(),hits.end(),[](const Hit&a,const Hit&b){
  if(a.exactAlias!=b.exactAlias)return a.exactAlias>b.exactAlias;
  bool aDirect=a.score>=700,bDirect=b.score>=700;
  if(aDirect!=bDirect)return aDirect>bDirect;
  if(a.favorite!=b.favorite)return a.favorite>b.favorite;
  if(a.score!=b.score)return a.score>b.score;
  // Preserve AE catalog order for equally relevant results, as in FX Console.
  return a.index<b.index;
 });if(hits.size()>limit)hits.resize(limit);return hits;
}
}}




