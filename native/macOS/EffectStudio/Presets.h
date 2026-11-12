#pragma once
#include "SearchPanel.h"
namespace effectstudio_mac { namespace presets {
struct Result {std::vector<Entry> entries;bool incomplete=false;};
std::vector<std::string> Roots();
Result Scan(const std::vector<std::string>& roots);
bool IsPreset(const std::wstring& path);
std::string JSString(const std::wstring& value);
std::string ApplyScript(long compId,const std::vector<long>& indices,const std::wstring& path);
}}
