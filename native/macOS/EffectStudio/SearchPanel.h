#pragma once
#include <string>
#include <vector>
#include <cstdint>
namespace effectstudio_mac {
struct Entry { std::string id; std::wstring name, category; std::vector<std::wstring> aliases; };
// Generation identifies a host-owned snapshot of comp + layer IDs. The AE idle
// callback MUST revalidate that snapshot before opening its single undo group.
struct Choice { std::string id; std::uint64_t generation=0; };
bool OpenSearch(const std::vector<Entry>& catalog, unsigned selectedCount, std::uint64_t generation);
bool TakeChoice(Choice& choice);
void CloseSearch();
void Shutdown();
bool IsOpen();
// Host callbacks alone perform AE API calls; AppKit delegates only queue IDs.
}
