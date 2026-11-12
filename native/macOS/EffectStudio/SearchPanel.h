#pragma once
#include <string>
#include <vector>
#include <cstdint>
namespace effectstudio_mac {
struct Entry { std::string id; std::wstring name, category; std::vector<std::wstring> aliases; };
// Generation identifies a host-owned snapshot of comp + layer IDs. The AE idle
// callback MUST revalidate that snapshot before opening its single undo group.
struct Choice { std::string id; std::uint64_t generation=0; };
enum class HostAction { Capture, SaveCapture };
bool OpenSearch(const std::vector<Entry>& catalog, unsigned selectedCount, std::uint64_t generation);
bool TakeChoice(Choice& choice);
bool TakeHostAction(HostAction& action,std::uint64_t& generation);
void CloseSearch();
void Shutdown();
bool IsOpen();
bool IsBrowserOpen();
void UpdateSelection(unsigned count,std::uint64_t generation);
// Host callbacks alone perform AE API calls; AppKit delegates only queue IDs.
}
