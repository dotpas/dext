#ifndef DextMapResolve_HPP
#define DextMapResolve_HPP

/**
 * Resolve a code address against the ILINK .map next to the running EXE.
 *
 * Stock dunitrtl AddressInfo() is only "$XXXXXXXX" (no JCL). The .map is large
 * with DetailedSegments, but preferred VAs do not match ASLR — convert with
 * GetModuleHandle(NULL) the same way Dext.Core.Debug does (RVA − $1000).
 *
 * C++ ILINK maps have Publics by Value; they typically have no "Line numbers for".
 */

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

namespace Dext {
namespace Testing {

/** Append diagnostics to %TEMP%\DextStackCapture.log (and OutputDebugString). */
inline void StackDiagLog(const char* msg)
{
  if (!msg) return;
  OutputDebugStringA("[DextStack] ");
  OutputDebugStringA(msg);
  OutputDebugStringA("\n");

  wchar_t tempDir[MAX_PATH];
  DWORD n = GetTempPathW(MAX_PATH, tempDir);
  if (n == 0 || n >= MAX_PATH)
    return;
  std::wstring path(tempDir, n);
  path += L"DextStackCapture.log";
  FILE* f = _wfopen(path.c_str(), L"ab");
  if (!f)
    return;
  char stamp[64];
  time_t now = time(nullptr);
  struct tm tmv;
  localtime_s(&tmv, &now);
  std::strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tmv);
  std::fprintf(f, "[%s] %s\n", stamp, msg);
  std::fclose(f);
}

inline void StackDiagLogf(const char* fmt, ...)
{
  char buf[1024];
  va_list ap;
  va_start(ap, fmt);
  std::vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  StackDiagLog(buf);
}

struct MapSymbol {
  unsigned Offset; // 0001: segment offset (CODE), same as Dext.Core.Debug map RVA
  std::string Name;
};

struct MapModuleRange {
  unsigned Start;
  unsigned Length;
  std::string ModulePath; // M=... from Detailed map of segments
};

inline std::wstring ExeMapPathW()
{
  wchar_t buf[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, buf, MAX_PATH);
  if (n == 0 || n >= MAX_PATH)
    return std::wstring();
  std::wstring path(buf, n);
  size_t dot = path.find_last_of(L'.');
  if (dot != std::wstring::npos)
    path = path.substr(0, dot);
  return path + L".map";
}

/** Call once at process start so the next cycle can correlate a Host run. */
inline void StackDiagRunBanner(const char* where)
{
  wchar_t exe[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
  char exeA[MAX_PATH * 2] = "(unknown)";
  if (n > 0 && n < MAX_PATH)
    WideCharToMultiByte(CP_UTF8, 0, exe, -1, exeA, sizeof(exeA), nullptr, nullptr);

  std::wstring mapW = ExeMapPathW();
  const bool mapOk = !mapW.empty() && GetFileAttributesW(mapW.c_str()) != INVALID_FILE_ATTRIBUTES;

  StackDiagLog("======== DextStack RUN START ========");
  StackDiagLogf("banner where=%s", where ? where : "(null)");
  StackDiagLogf("banner exe=%s", exeA);
  StackDiagLogf("banner mapExists=%d", mapOk ? 1 : 0);
}

inline bool ParseHex8(const char* p, unsigned& out)
{
  out = 0;
  for (int i = 0; i < 8; ++i) {
    char c = p[i];
    unsigned v;
    if (c >= '0' && c <= '9') v = static_cast<unsigned>(c - '0');
    else if (c >= 'A' && c <= 'F') v = static_cast<unsigned>(c - 'A' + 10);
    else if (c >= 'a' && c <= 'f') v = static_cast<unsigned>(c - 'a' + 10);
    else return false;
    out = (out << 4) | v;
  }
  return true;
}

inline std::string CleanMapSymbolName(std::string name)
{
  // "__fastcall TSmokeTestCase::TestIntentionalFail()" → "TSmokeTestCase::TestIntentionalFail"
  auto startsWithCI = [](const std::string& s, const char* pre) -> bool {
    size_t n = std::strlen(pre);
    if (s.size() < n) return false;
    for (size_t i = 0; i < n; ++i) {
      char a = s[i], b = pre[i];
      if (a >= 'A' && a <= 'Z') a = static_cast<char>(a - 'A' + 'a');
      if (b >= 'A' && b <= 'Z') b = static_cast<char>(b - 'A' + 'a');
      if (a != b) return false;
    }
    return true;
  };
  static const char* prefixes[] = {
    "__fastcall ", "__cdecl ", "__stdcall ", "__thiscall ", "pascal "
  };
  for (const char* pre : prefixes) {
    if (startsWithCI(name, pre)) {
      name = name.substr(std::strlen(pre));
      break;
    }
  }
  // Drop C++ parameter list: "TFoo::Bar(int, char*)" → "TFoo::Bar"
  // (must not strip only trailing ')' — that leaves "Bar(int" and breaks " (File.cpp)").
  size_t paren = name.find('(');
  if (paren != std::string::npos)
    name = name.substr(0, paren);
  while (!name.empty() && (name.back() == ' ' || name.back() == ')'))
    name.pop_back();
  return name;
}

inline std::string ModulePathToSourceHint(const std::string& modulePath)
{
  // ...\SMOKETESTCASE.OBJ → SmokeTestCase.cpp
  std::string base = modulePath;
  size_t slash = base.find_last_of("\\/");
  if (slash != std::string::npos)
    base = base.substr(slash + 1);
  size_t pipe = base.find('|');
  if (pipe != std::string::npos)
    base = base.substr(pipe + 1); // RTL.LIB|System → System
  size_t dot = base.find_last_of('.');
  if (dot != std::string::npos)
    base = base.substr(0, dot);
  if (base.empty())
    return std::string();
  // Keep original casing from path when possible; OBJ names are often upper.
  return base + ".cpp";
}

inline bool LoadMapPublicsAndModules(const std::wstring& mapPath,
  std::vector<MapSymbol>& symbols, std::vector<MapModuleRange>& modules)
{
  symbols.clear();
  modules.clear();
  FILE* f = _wfopen(mapPath.c_str(), L"rb");
  if (!f)
    return false;

  char line[2048];
  enum { None, Detailed, Publics } section = None;
  while (fgets(line, sizeof(line), f)) {
    // trim CR/LF
    size_t len = std::strlen(line);
    while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
      line[--len] = 0;

    if (std::strstr(line, "Detailed map of segments") != nullptr) {
      section = Detailed;
      continue;
    }
    if (std::strstr(line, "Address Publics by Value") != nullptr) {
      section = Publics;
      continue;
    }
    if (std::strstr(line, "Address Publics by Name") != nullptr) {
      if (section == Publics)
        break; // prefer Value; Name is duplicate
      section = None;
      continue;
    }
    if (std::strstr(line, "Line numbers for") != nullptr) {
      section = None;
      continue;
    }

    if (section == Detailed) {
      //  0001:0002BBE4 00000B3E C=CODE ... M=...\SMOKETESTCASE.OBJ
      if (len < 20 || line[0] != ' ' || std::strncmp(line + 1, "0001:", 5) != 0)
        continue;
      unsigned start = 0, length = 0;
      if (!ParseHex8(line + 6, start))
        continue;
      const char* p = line + 14;
      while (*p == ' ') ++p;
      if (!ParseHex8(p, length))
        continue;
      const char* m = std::strstr(line, "M=");
      if (!m)
        continue;
      m += 2;
      const char* end = m;
      while (*end && *end != ' ' && *end != '\t') ++end;
      MapModuleRange r;
      r.Start = start;
      r.Length = length;
      r.ModulePath.assign(m, end);
      modules.push_back(r);
    }
    else if (section == Publics) {
      //  0001:0002C178  __fastcall TSmokeTestCase::TestIntentionalFail()
      if (len < 15 || line[0] != ' ' || std::strncmp(line + 1, "0001:", 5) != 0)
        continue;
      unsigned off = 0;
      if (!ParseHex8(line + 6, off))
        continue;
      const char* name = line + 14;
      while (*name == ' ') ++name;
      if (*name == 0 || name[0] == '.')
        continue;
      MapSymbol s;
      s.Offset = off;
      s.Name = CleanMapSymbolName(name);
      if (!s.Name.empty())
        symbols.push_back(s);
    }
  }
  fclose(f);
  return !symbols.empty();
}

inline bool LookupAddressInMap(
  void* address,
  const std::vector<MapSymbol>& symbols,
  const std::vector<MapModuleRange>& modules,
  uintptr_t moduleBase,
  std::string& outMethod,
  std::string& outFileHint)
{
  outMethod.clear();
  outFileHint.clear();
  if (!address || symbols.empty())
    return false;

  const uintptr_t addr = reinterpret_cast<uintptr_t>(address);
  if (addr < moduleBase)
    return false;

  uintptr_t offset = addr - moduleBase;
  // PE: CODE at RVA $1000; ILINK 0001: offsets match Address − base − $1000
  if (offset >= 0x1000)
    offset -= 0x1000;

  int best = -1;
  for (int i = 0; i < static_cast<int>(symbols.size()); ++i) {
    if (symbols[static_cast<size_t>(i)].Offset <= offset) {
      if (best < 0 || symbols[static_cast<size_t>(i)].Offset >= symbols[static_cast<size_t>(best)].Offset)
        best = i;
    }
  }
  if (best < 0)
    return false;

  const MapSymbol& sym = symbols[static_cast<size_t>(best)];
  const unsigned delta = static_cast<unsigned>(offset - sym.Offset);
  if (delta > 0x10000)
    return false;

  outMethod = sym.Name;
  for (const auto& m : modules) {
    if (offset >= m.Start && offset < m.Start + m.Length) {
      outFileHint = ModulePathToSourceHint(m.ModulePath);
      break;
    }
  }
  return !outMethod.empty();
}

inline std::string FormatIndexedFrame(int index, const std::string& method, const std::string& fileHint)
{
  // Use " @ File.cpp" — NOT " (File.cpp)" — because C++ symbols already contain '('.
  char buf[512];
  if (!fileHint.empty())
    std::snprintf(buf, sizeof(buf), "[%d] %s @ %s", index, method.c_str(), fileHint.c_str());
  else
    std::snprintf(buf, sizeof(buf), "[%d] %s", index, method.c_str());
  return std::string(buf);
}

/**
 * Map code pointer → "[0] Method (Hint.cpp)" using EXE .map + live image base.
 */
inline std::string ResolveAddressViaExeMap(void* address)
{
  HMODULE mod = GetModuleHandleW(nullptr);
  if (!mod)
    return std::string();

  std::wstring mapPath = ExeMapPathW();
  if (mapPath.empty())
    return std::string();

  std::vector<MapSymbol> symbols;
  std::vector<MapModuleRange> modules;
  if (!LoadMapPublicsAndModules(mapPath, symbols, modules))
    return std::string();

  std::string method, fileHint;
  if (!LookupAddressInMap(address, symbols, modules, reinterpret_cast<uintptr_t>(mod), method, fileHint))
    return std::string();
  return FormatIndexedFrame(0, method, fileHint);
}

inline std::string ToUpperAscii(std::string s)
{
  for (char& c : s) {
    if (c >= 'a' && c <= 'z')
      c = static_cast<char>(c - 'a' + 'A');
  }
  return s;
}

/** True = DUnit/RTL/OS/startup — not the failing user chain. */
inline bool IsNoisyStackSymbol(const std::string& method, const std::string& fileHint = std::string())
{
  if (method.empty()) return true;
  auto has = [&](const char* token) {
    return method.find(token) != std::string::npos;
  };
  const std::string fileU = ToUpperAscii(fileHint);
  if (has("CaptureResolvedCallStack") || has("NoteFailureStack") || has("TakePendingFailureStack"))
    return true;
  if (has("GTestFailureStackOrLocation") || has("DextGTestListener"))
    return true;
  if (has("RtlCaptureStackBackTrace") || has("CaptureStackBackTrace"))
    return true;
  if (has("KERNEL32") || has("ntdll") || has("KiUser"))
    return true;
  if (has("Testframework::") || has("Texttestrunner::"))
    return true;
  // Adapter / Host only — do not blanket-filter Dext::Testing (smoke helpers live there).
  if (has("Dext::Testing::HostClient") || has("Dext::Testing::RunDext") ||
      has("Dext::Testing::Discover") || has("Dext::Testing::DextGTest") ||
      has("Dext::Testing::DextDUnit"))
    return true;
  if (has("testing::") || has("gtest") || has("GTEST_"))
    return true;
  if (fileU == "PROGRAM.CPP" || fileU.find("C0X32") != std::string::npos)
    return true;
  if (fileU.find("GTEST") != std::string::npos || fileU.find("GMOCK") != std::string::npos)
    return true;
  return false;
}

/**
 * Keep frames from the test project .obj — drop Embarcadero LIB / RTL modules.
 * ModulePath comes from MAP M=... (full path or LIB|unit).
 */
inline bool IsProjectStackModule(const std::string& modulePath, const std::string& fileHint)
{
  if (fileHint.empty())
    return false;
  const std::string u = ToUpperAscii(modulePath);
  if (u.find("EMBARCADERO") != std::string::npos)
    return false;
  if (u.find("\\LIB\\") != std::string::npos || u.find("/LIB/") != std::string::npos)
    return false;
  if (u.find(".LIB|") != std::string::npos || u.find(".LIB\\") != std::string::npos)
    return false;
  if (ToUpperAscii(fileHint) == "PROGRAM.CPP")
    return false;
  return true;
}

inline std::string ModulePathForOffset(
  unsigned offset, const std::vector<MapModuleRange>& modules)
{
  for (const auto& m : modules) {
    if (offset >= m.Start && offset < m.Start + m.Length)
      return m.ModulePath;
  }
  return std::string();
}

/**
 * Resolve raw addresses via EXE .map. Keeps user chain only, then stops at runner/RTL.
 */
inline std::string ResolveFrameAddresses(void* const* frames, unsigned count)
{
  if (!frames || count == 0) {
    StackDiagLog("ResolveFrameAddresses: no frames");
    return std::string();
  }

  HMODULE mod = GetModuleHandleW(nullptr);
  if (!mod) {
    StackDiagLog("ResolveFrameAddresses: GetModuleHandle NULL");
    return std::string();
  }

  std::wstring mapPath = ExeMapPathW();
  if (mapPath.empty()) {
    StackDiagLog("ResolveFrameAddresses: empty map path");
    return std::string();
  }

  char mapA[MAX_PATH];
  WideCharToMultiByte(CP_UTF8, 0, mapPath.c_str(), -1, mapA, MAX_PATH, nullptr, nullptr);
  const DWORD mapAttr = GetFileAttributesW(mapPath.c_str());
  StackDiagLogf("ResolveFrameAddresses: map=%s exists=%d frames=%u",
    mapA, mapAttr != INVALID_FILE_ATTRIBUTES ? 1 : 0, count);

  std::vector<MapSymbol> symbols;
  std::vector<MapModuleRange> modules;
  if (!LoadMapPublicsAndModules(mapPath, symbols, modules)) {
    StackDiagLog("ResolveFrameAddresses: LoadMapPublicsAndModules FAILED");
    return std::string();
  }
  StackDiagLogf("ResolveFrameAddresses: symbols=%u modules=%u",
    static_cast<unsigned>(symbols.size()), static_cast<unsigned>(modules.size()));

  const uintptr_t base = reinterpret_cast<uintptr_t>(mod);
  std::string result;
  int outIndex = 0;
  bool sawProjectFrame = false;
  unsigned lookupFail = 0, noisySkip = 0, kept = 0;
  for (unsigned i = 0; i < count && outIndex < 16; ++i) {
    if (!frames[i])
      continue;
    std::string method, fileHint;
    if (!LookupAddressInMap(frames[i], symbols, modules, base, method, fileHint)) {
      ++lookupFail;
      StackDiagLogf("  frame[%u] addr=%p lookup FAIL", i, frames[i]);
      continue;
    }

    uintptr_t offset = reinterpret_cast<uintptr_t>(frames[i]) - base;
    if (offset >= 0x1000)
      offset -= 0x1000;
    const std::string modPath = ModulePathForOffset(static_cast<unsigned>(offset), modules);
    const bool noisy = IsNoisyStackSymbol(method, fileHint);
    bool project = IsProjectStackModule(modPath, fileHint);
    if (!project && !noisy && !method.empty() &&
        (method.find("SmokeGTest::") != std::string::npos ||
         method.find("TestBody") != std::string::npos))
      project = true;

    StackDiagLogf("  frame[%u] method=%s file=%s noisy=%d project=%d",
      i, method.c_str(), fileHint.c_str(), noisy ? 1 : 0, project ? 1 : 0);

    if (noisy || !project) {
      ++noisySkip;
      if (sawProjectFrame)
        break;
      continue;
    }

    if (!result.empty())
      result += "\n";
    result += FormatIndexedFrame(outIndex, method, fileHint);
    ++outIndex;
    ++kept;
    sawProjectFrame = true;
  }
  StackDiagLogf("ResolveFrameAddresses: kept=%u lookupFail=%u noisySkip=%u outChars=%u",
    kept, lookupFail, noisySkip, static_cast<unsigned>(result.size()));
  return result;
}

/**
 * Capture live call stack and resolve via EXE .map (ASLR-safe).
 * Win32 Clang / bcc32c often returns empty CaptureStackBackTrace without
 * frame pointers — fall back to __builtin_return_address for a few callers.
 */
inline std::string CaptureResolvedCallStack(unsigned framesToSkip)
{
  void* frames[48];
  const USHORT n = CaptureStackBackTrace(framesToSkip, 48, frames, nullptr);
  StackDiagLogf("CaptureResolvedCallStack: skip=%u CaptureStackBackTrace n=%u",
    framesToSkip, static_cast<unsigned>(n));
  std::string result = ResolveFrameAddresses(frames, n);
  if (!result.empty()) {
    StackDiagLogf("CaptureResolvedCallStack: WinAPI path OK chars=%u",
      static_cast<unsigned>(result.size()));
    return result;
  }

#if defined(__clang__) || defined(__GNUC__)
  StackDiagLog("CaptureResolvedCallStack: trying __builtin_return_address");
  void* builtin[5] = {};
  unsigned b = 0;
  if (framesToSkip == 0)
    builtin[b++] = __builtin_return_address(0);
  builtin[b++] = __builtin_return_address(1);
  builtin[b++] = __builtin_return_address(2);
  builtin[b++] = __builtin_return_address(3);
  builtin[b++] = __builtin_return_address(4);
  result = ResolveFrameAddresses(builtin, b);
  StackDiagLogf("CaptureResolvedCallStack: builtin path chars=%u",
    static_cast<unsigned>(result.size()));
#endif
  return result;
}

/**
 * Pending stack snapped just before CheckEquals/throw.
 * Process-wide (not thread_local): bcc32c cannot destroy non-trivial TLS yet,
 * and the DUnit Host path runs the suite on one thread.
 */
inline std::string& PendingFailureStackStorage()
{
  static std::string s;
  return s;
}

/**
 * Explicit call-chain breadcrumbs — reliable on Win32 Clang where
 * CaptureStackBackTrace / __builtin_return_address often yield nothing useful.
 * Push with FailureStackScope in Gateway → Auditor → TEST, then NoteFailureStack().
 */
struct FailureStackFrame {
  const char* Method;
  const char* FileHint;
};

inline std::vector<FailureStackFrame>& FailureStackBreadcrumbs()
{
  static std::vector<FailureStackFrame> s;
  return s;
}

struct FailureStackScope {
  FailureStackScope(const char* method, const char* fileHint = "")
  {
    FailureStackBreadcrumbs().push_back(FailureStackFrame{method, fileHint});
    StackDiagLogf("FailureStackScope PUSH depth=%u method=%s file=%s",
      static_cast<unsigned>(FailureStackBreadcrumbs().size()),
      method ? method : "(null)",
      fileHint ? fileHint : "");
  }
  ~FailureStackScope()
  {
    auto& b = FailureStackBreadcrumbs();
    if (!b.empty()) {
      StackDiagLogf("FailureStackScope POP was=%s depth→%u",
        b.back().Method ? b.back().Method : "(null)",
        static_cast<unsigned>(b.size() - 1));
      b.pop_back();
    }
  }
  FailureStackScope(const FailureStackScope&) = delete;
  FailureStackScope& operator=(const FailureStackScope&) = delete;
};

inline std::string FormatBreadcrumbStack()
{
  const auto& b = FailureStackBreadcrumbs();
  StackDiagLogf("FormatBreadcrumbStack: depth=%u", static_cast<unsigned>(b.size()));
  if (b.empty())
    return std::string();
  // Innermost first (top of stack): Auditor → Gateway → Test
  std::string result;
  int outIndex = 0;
  for (int i = static_cast<int>(b.size()) - 1; i >= 0; --i) {
    if (!result.empty())
      result += "\n";
    const FailureStackFrame& fr = b[static_cast<size_t>(i)];
    result += FormatIndexedFrame(outIndex++, fr.Method,
      fr.FileHint ? fr.FileHint : "");
    StackDiagLogf("  crumb[%d] %s @ %s", outIndex - 1,
      fr.Method ? fr.Method : "", fr.FileHint ? fr.FileHint : "");
  }
  return result;
}

__declspec(noinline) inline void NoteFailureStack()
{
  // 1) Breadcrumbs (preferred — works without frame pointers / MAP unwind)
  // 2) CaptureStackBackTrace / __builtin_return_address + MAP
  // Host JSON with only "[0] DeepCallFail @ file:line" is the GTest location
  // fallback (EXPECT expression text like Ledger::Balance() is not a frame).
  StackDiagLog("NoteFailureStack: BEGIN");
  std::string result = FormatBreadcrumbStack();
  const char* pathUsed = "breadcrumb";
  if (result.empty()) {
    pathUsed = "builtin/map";
#if defined(__clang__) || defined(__GNUC__)
    void* builtin[5] = {
      __builtin_return_address(0),
      __builtin_return_address(1),
      __builtin_return_address(2),
      __builtin_return_address(3),
      __builtin_return_address(4)
    };
    result = ResolveFrameAddresses(builtin, 5);
#endif
  }
  if (result.empty()) {
    pathUsed = "CaptureStackBackTrace";
    result = CaptureResolvedCallStack(1);
  }
  PendingFailureStackStorage() = result;
  StackDiagLogf("NoteFailureStack: END path=%s pendingChars=%u",
    pathUsed, static_cast<unsigned>(result.size()));
  if (!result.empty())
    StackDiagLogf("NoteFailureStack: pending=\n%s", result.c_str());
  else
    StackDiagLog("NoteFailureStack: WARNING pending EMPTY — Host will use gtest fallback");
}

inline std::string TakePendingFailureStack()
{
  std::string s = PendingFailureStackStorage();
  PendingFailureStackStorage().clear();
  StackDiagLogf("TakePendingFailureStack: chars=%u%s",
    static_cast<unsigned>(s.size()),
    s.empty() ? " (EMPTY)" : "");
  if (!s.empty())
    StackDiagLogf("TakePendingFailureStack:\n%s", s.c_str());
  return s;
}

} // namespace Testing
} // namespace Dext

#endif
