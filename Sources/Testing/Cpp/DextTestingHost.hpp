#ifndef DextTestingHost_HPP
#define DextTestingHost_HPP

/**
 * Dext Test Explorer — HTTP Host client (same protocol as Dext.Testing.DUnit*.pas).
 *
 * Explorer launches:  MyTests.exe --port N -no-wait
 * Direct run:         MyTests.exe   (host switches are removed before the native runner)
 * Client talks to:    http://127.0.0.1:N/
 *   GET  /tests              -> {"SelectedTests":["Fixture.Name", ...]}
 *   POST /tests/results      -> JSON array of result objects
 *   POST /tests/started?totalcount=N  (optional run start)
 *   POST /tests/finished              (optional run end)
 *
 * Include this header from GTest / DUnit C++ adapters. Requires WinHTTP (Windows).
 */

#include <windows.h>
#include <winhttp.h>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <string>
#include <vector>
#include <sstream>

/* bcc64 (Clang 5, ilink64) links the import archive winhttp.a.
   bcc64x and Win32 link winhttp.lib. */
#if defined(_WIN64) && defined(__clang_major__) && (__clang_major__ < 15)
#pragma comment(lib, "winhttp.a")
#else
#pragma comment(lib, "winhttp.lib")
#endif

namespace Dext {
namespace Testing {

inline bool HasArgvFlag(int argc, char** argv, const char* flag)
{
  for (int i = 1; i < argc; ++i) {
    if (argv[i] && std::string(argv[i]) == flag)
      return true;
  }
  return false;
}

struct HostLaunch {
  int Port;
  bool Discover;
};

inline std::string LowerArg(const std::string& value)
{
  std::string s = value;
  for (size_t i = 0; i < s.size(); ++i)
    s[i] = static_cast<char>(std::tolower(static_cast<unsigned char>(s[i])));
  return s;
}

inline bool StartsWith(const std::string& value, const char* prefix)
{
  const std::string p(prefix);
  return value.size() >= p.size() && value.compare(0, p.size(), p) == 0;
}

/** Drop Explorer-only switches and remember --port / --discover.
 *  A direct run (no --port) leaves argv as a normal native invocation. */
inline HostLaunch TakeHostLaunch(int& argc, char** argv)
{
  HostLaunch launch;
  launch.Port = 0;
  launch.Discover = false;
  if (!argv) return launch;

  bool removed = false;
  int w = 1;
  for (int i = 1; i < argc; ++i) {
    std::string raw = argv[i] ? argv[i] : "";
    std::string a = LowerArg(raw);
    if (a == "--discover" || a == "-discover" || a == "/discover") {
      launch.Discover = true;
      removed = true;
      continue;
    }
    if (a == "--port" || a == "-port" || a == "/port") {
      if (i + 1 < argc) {
        std::string next = argv[i + 1] ? argv[i + 1] : "";
        if (!next.empty() && next[0] != '-' && next[0] != '/')
          launch.Port = std::atoi(argv[++i]);
      }
      removed = true;
      continue;
    }
    if (StartsWith(a, "--port=") || StartsWith(a, "--port:") ||
        StartsWith(a, "-port=") || StartsWith(a, "-port:") ||
        StartsWith(a, "/port=") || StartsWith(a, "/port:")) {
      const char* eq = std::strchr(raw.c_str(), '=');
      if (!eq) eq = std::strchr(raw.c_str(), ':');
      if (eq) launch.Port = std::atoi(eq + 1);
      removed = true;
      continue;
    }
    if (a == "-no-wait" || a == "/no-wait" || a == "--no-wait" ||
        a == "-no-dashboard" || a == "/no-dashboard" || a == "--no-dashboard" ||
        a == "-externalui" || a == "/externalui" || a == "--externalui" ||
        a == "-dext-headless" || a == "/dext-headless" || a == "--dext-headless") {
      removed = true;
      continue;
    }
    argv[w++] = argv[i];
  }
  argc = w;
  argv[w] = nullptr;
  if (launch.Port < 0) launch.Port = 0;
  if (!removed) return launch;

  std::wstring cmd;
  for (int i = 0; i < argc; ++i) {
    if (i) cmd.push_back(L' ');
    std::string raw = (argv[i]) ? argv[i] : "";
    int n = MultiByteToWideChar(CP_ACP, 0, raw.c_str(), -1, nullptr, 0);
    std::wstring wide(n > 1 ? static_cast<size_t>(n - 1) : 0, L'\0');
    if (n > 1)
      MultiByteToWideChar(CP_ACP, 0, raw.c_str(), -1, &wide[0], n);
    const bool quote = wide.empty() || wide.find(L' ') != std::wstring::npos ||
      wide.find(L'"') != std::wstring::npos;
    if (quote) cmd.push_back(L'"');
    cmd += wide;
    if (quote) cmd.push_back(L'"');
  }
  wchar_t* processCmd = GetCommandLineW();
  if (processCmd && cmd.size() <= std::wcslen(processCmd)) {
    std::wmemcpy(processCmd, cmd.c_str(), cmd.size());
    processCmd[cmd.size()] = L'\0';
  }
  return launch;
}

inline bool ParsePortFromArgv(int argc, char** argv, int& outPort)
{
  outPort = 0;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i] ? argv[i] : "";
    if ((a == "--port" || a == "-port") && i + 1 < argc) {
      outPort = atoi(argv[++i]);
      return outPort > 0;
    }
    // Also accept --port=N
    if (a.rfind("--port=", 0) == 0) {
      outPort = atoi(a.c_str() + 7);
      return outPort > 0;
    }
  }
  return false;
}

class HostClient {
public:
  explicit HostClient(int port)
    : FPort(port), FSession(nullptr), FConnect(nullptr)
  {
    FBaseHost = L"127.0.0.1";
    FSession = WinHttpOpen(L"DextTestingHost/1.0",
      WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (FSession)
      FConnect = WinHttpConnect(FSession, FBaseHost.c_str(),
        static_cast<INTERNET_PORT>(FPort), 0);
  }

  ~HostClient()
  {
    if (FConnect) WinHttpCloseHandle(FConnect);
    if (FSession) WinHttpCloseHandle(FSession);
  }

  /** WinHttpConnect does not prove the Host is up — probe GET /tests. */
  bool Ok() const
  {
    if (!FConnect) return false;
    std::string body;
    return const_cast<HostClient*>(this)->Http("GET", L"/tests", "", body);
  }

  std::vector<std::string> GetSelectedTests()
  {
    std::vector<std::string> result;
    std::string body;
    if (!Http("GET", L"/tests", "", body))
      return result;
    // Minimal parse: collect quoted strings inside SelectedTests array
    auto pos = body.find("SelectedTests");
    if (pos == std::string::npos)
      return result;
    pos = body.find('[', pos);
    auto end = body.find(']', pos);
    if (pos == std::string::npos || end == std::string::npos)
      return result;
    std::string arr = body.substr(pos + 1, end - pos - 1);
    size_t i = 0;
    while (i < arr.size()) {
      auto q1 = arr.find('"', i);
      if (q1 == std::string::npos) break;
      auto q2 = arr.find('"', q1 + 1);
      if (q2 == std::string::npos) break;
      result.push_back(arr.substr(q1 + 1, q2 - q1 - 1));
      i = q2 + 1;
    }
    return result;
  }

  void PostResultsJson(const std::string& jsonArray)
  {
    std::string ignored;
    Http("POST", L"/tests/results", jsonArray, ignored);
  }

  void PostStarted(int totalCount)
  {
    std::wstringstream path;
    path << L"/tests/started?totalcount=" << totalCount;
    std::string ignored;
    Http("POST", path.str().c_str(), "", ignored);
  }

  void PostFinished()
  {
    std::string ignored;
    Http("POST", L"/tests/finished", "", ignored);
  }

  static std::string EscapeJson(const std::string& s)
  {
    std::string o;
    o.reserve(s.size() + 8);
    for (char c : s) {
      switch (c) {
        case '\\': o += "\\\\"; break;
        case '"':  o += "\\\""; break;
        case '\n': o += "\\n"; break;
        case '\r': o += "\\r"; break;
        case '\t': o += "\\t"; break;
        default:   o += c; break;
      }
    }
    return o;
  }

  static std::string MakeResultJson(
    const std::string& resultType,
    const std::string& fixture,
    const std::string& testName,
    const std::string& methodName,
    const std::string& unitName,
    const std::string& message,
    int durationMs,
    const std::string& stackTrace = "",
    int lineNumber = 0)
  {
    std::ostringstream o;
    o << "[{"
      << "\"resulttype\":\"" << EscapeJson(resultType) << "\","
      << "\"testname\":\"" << EscapeJson(testName) << "\","
      << "\"fixturename\":\"" << EscapeJson(fixture) << "\","
      << "\"duration\":" << durationMs << ","
      << "\"exceptionmessage\":\"" << EscapeJson(message) << "\","
      << "\"stacktrace\":\"" << EscapeJson(stackTrace) << "\","
      << "\"unitname\":\"" << EscapeJson(unitName) << "\","
      << "\"classname\":\"" << EscapeJson(fixture) << "\","
      << "\"methodname\":\"" << EscapeJson(methodName) << "\","
      << "\"linenumber\":" << lineNumber << ","
      << "\"path\":\"\","
      << "\"status\":\"\""
      << "}]";
    return o.str();
  }

private:
  int FPort;
  HINTERNET FSession;
  HINTERNET FConnect;
  std::wstring FBaseHost;

  bool Http(const char* method, const wchar_t* path, const std::string& body, std::string& outBody)
  {
    outBody.clear();
    if (!FConnect) return false;
    std::wstring wmethod;
    for (const char* p = method; *p; ++p) wmethod.push_back(static_cast<wchar_t>(*p));

    HINTERNET req = WinHttpOpenRequest(FConnect, wmethod.c_str(), path,
      nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
    if (!req) return false;

    BOOL ok;
    if (body.empty()) {
      ok = WinHttpSendRequest(req, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
        WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
    } else {
      std::wstring headers = L"Content-Type: application/json\r\n";
      ok = WinHttpSendRequest(req, headers.c_str(), static_cast<DWORD>(-1),
        (LPVOID)body.data(), static_cast<DWORD>(body.size()),
        static_cast<DWORD>(body.size()), 0);
    }
    if (!ok) { WinHttpCloseHandle(req); return false; }
    if (!WinHttpReceiveResponse(req, nullptr)) { WinHttpCloseHandle(req); return false; }

    DWORD avail = 0;
    while (WinHttpQueryDataAvailable(req, &avail) && avail > 0) {
      std::string chunk(avail, '\0');
      DWORD read = 0;
      if (!WinHttpReadData(req, &chunk[0], avail, &read)) break;
      chunk.resize(read);
      outBody += chunk;
      avail = 0;
    }
    WinHttpCloseHandle(req);
    return true;
  }
};

} // namespace Testing
} // namespace Dext

#endif
