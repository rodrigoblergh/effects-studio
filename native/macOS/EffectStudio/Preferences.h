#pragma once
#include <array>
#include <map>
#include <set>
#include <string>
namespace effectstudio_mac {
struct Preferences {
 std::set<std::string> favorites;
 std::map<std::string,std::wstring> aliases;
 std::array<std::string,9> shortcuts;
 bool expanded=false;
 bool Load(std::string& error);
 bool Save(std::string& error) const;
};
}
