#ifndef DextReportWriter_HPP
#define DextReportWriter_HPP

/**
 * Same report switches as a Delphi Dext test exe (Dext.Testing.Fluent / Dext.Testing.Report):
 *   -junit:out.xml   -json:out.json   -html:out.html   -sonar:out.xml
 * Also accepts /junit: and --junit= (and the same for json, html, sonar, sonarqube).
 *
 * JUnit, JSON and Sonar generic testExecutions follow Dext.Testing.Report.
 * HTML is a plain table of the same rows (the Delphi HTML skin stays in the IDE export).
 *
 * Call CaptureArgv before Google Test's InitGoogleTest so those switches are not
 * treated as a test filter. Adapters Add() each finished test and Write() at the end.
 */

#include <cstdio>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace Dext {
namespace Testing {

enum class ReportStatus {
  None = 0,
  Passed = 1,
  Failed = 2,
  Skipped = 3,
  Timeout = 4,
  Error = 5
};

struct ReportCase {
  std::string Fixture;
  std::string Name;
  std::string File;
  std::string Message;
  std::string Stack;
  int DurationMs = 0;
  ReportStatus Status = ReportStatus::None;
};

class ReportSink {
public:
  static ReportSink& Instance()
  {
    static ReportSink sink;
    return sink;
  }

  /** Pull -junit: / -json: / -html: / -sonar: out of argv. Safe before InitGoogleTest. */
  static void CaptureArgv(int& argc, char** argv)
  {
    if (!argv) return;
    int w = 1;
    for (int i = 1; i < argc; ++i) {
      std::string a = argv[i] ? argv[i] : "";
      std::string path;
      if (TakeSwitch(a, "junit", path))
        Instance().FJunit = path;
      else if (TakeSwitch(a, "json", path))
        Instance().FJson = path;
      else if (TakeSwitch(a, "html", path))
        Instance().FHtml = path;
      else if (TakeSwitch(a, "sonarqube", path) || TakeSwitch(a, "sonar", path))
        Instance().FSonar = path;
      else {
        argv[w++] = argv[i];
        continue;
      }
    }
    argc = w;
    argv[w] = nullptr;
  }

  bool Enabled() const
  {
    return !FJunit.empty() || !FJson.empty() || !FHtml.empty() || !FSonar.empty();
  }

  void Add(const std::string& fixture, const std::string& name, ReportStatus status,
    const std::string& message, const std::string& stack, int durationMs,
    const std::string& file = "")
  {
    if (!Enabled()) return;
    ReportCase c;
    c.Fixture = fixture.empty() ? "Default" : fixture;
    c.Name = name;
    c.File = file.empty() ? c.Fixture : file;
    c.Message = message;
    c.Stack = stack;
    c.DurationMs = durationMs < 0 ? 0 : durationMs;
    c.Status = status;
    FCases.push_back(c);
  }

  void Write() const
  {
    if (!Enabled()) return;
    if (!FJunit.empty()) WriteFile(FJunit, JUnitXml());
    if (!FJson.empty()) WriteFile(FJson, JsonText());
    if (!FSonar.empty()) WriteFile(FSonar, SonarXml());
    if (!FHtml.empty()) WriteFile(FHtml, HtmlText());
  }

private:
  std::string FJunit;
  std::string FJson;
  std::string FHtml;
  std::string FSonar;
  std::vector<ReportCase> FCases;

  static bool TakeSwitch(const std::string& a, const char* key, std::string& path)
  {
    const std::string k(key);
    const std::string dash = "-" + k + ":";
    const std::string slash = "/" + k + ":";
    const std::string longe = "--" + k + "=";
    if (a.rfind(dash, 0) == 0) { path = a.substr(dash.size()); return true; }
    if (a.rfind(slash, 0) == 0) { path = a.substr(slash.size()); return true; }
    if (a.rfind(longe, 0) == 0) { path = a.substr(longe.size()); return true; }
    return false;
  }

  static void WriteFile(const std::string& path, const std::string& body)
  {
    std::ofstream f(path.c_str(), std::ios::binary);
    if (!f) return;
    f << body;
  }

  static std::string XmlEscape(const std::string& s)
  {
    std::string o;
    o.reserve(s.size());
    for (char c : s) {
      switch (c) {
        case '&': o += "&amp;"; break;
        case '<': o += "&lt;"; break;
        case '>': o += "&gt;"; break;
        case '"': o += "&quot;"; break;
        default: o += c; break;
      }
    }
    return o;
  }

  static std::string JsonEscape(const std::string& s)
  {
    std::string o;
    for (unsigned char c : s) {
      switch (c) {
        case '\\': o += "\\\\"; break;
        case '"': o += "\\\""; break;
        case '\n': o += "\\n"; break;
        case '\r': o += "\\r"; break;
        case '\t': o += "\\t"; break;
        default:
          if (c < 0x20) {
            char buf[8];
            std::snprintf(buf, sizeof(buf), "\\u%04x", c);
            o += buf;
          } else o += static_cast<char>(c);
          break;
      }
    }
    return o;
  }

  static std::string Seconds(int ms)
  {
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%.3f", ms / 1000.0);
    return buf;
  }

  static std::string NowStamp()
  {
    std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &t);
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d",
      tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
    return buf;
  }

  std::vector<std::string> FixturesInOrder() const
  {
    std::vector<std::string> names;
    for (const auto& c : FCases) {
      bool seen = false;
      for (const auto& n : names)
        if (n == c.Fixture) { seen = true; break; }
      if (!seen) names.push_back(c.Fixture);
    }
    return names;
  }

  std::string JUnitXml() const
  {
    int tests = 0, failures = 0, errors = 0, skipped = 0, totalMs = 0;
    for (const auto& c : FCases) {
      ++tests;
      totalMs += c.DurationMs;
      if (c.Status == ReportStatus::Failed || c.Status == ReportStatus::Timeout) ++failures;
      else if (c.Status == ReportStatus::Error) ++errors;
      else if (c.Status == ReportStatus::Skipped) ++skipped;
    }
    std::ostringstream o;
    o << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    o << "<testsuites tests=\"" << tests << "\" failures=\"" << failures
      << "\" errors=\"" << errors << "\" skipped=\"" << skipped
      << "\" time=\"" << Seconds(totalMs) << "\">\n";
    const std::string stamp = NowStamp();
    for (const auto& fixture : FixturesInOrder()) {
      int ft = 0, ff = 0, fe = 0, fs = 0, fms = 0;
      for (const auto& c : FCases) {
        if (c.Fixture != fixture) continue;
        ++ft;
        fms += c.DurationMs;
        if (c.Status == ReportStatus::Failed || c.Status == ReportStatus::Timeout) ++ff;
        else if (c.Status == ReportStatus::Error) ++fe;
        else if (c.Status == ReportStatus::Skipped) ++fs;
      }
      o << "  <testsuite name=\"" << XmlEscape(fixture) << "\" tests=\"" << ft
        << "\" failures=\"" << ff << "\" errors=\"" << fe << "\" skipped=\"" << fs
        << "\" time=\"" << Seconds(fms) << "\" timestamp=\"" << stamp << "\">\n";
      for (const auto& c : FCases) {
        if (c.Fixture != fixture) continue;
        o << "    <testcase classname=\"" << XmlEscape(c.Fixture)
          << "\" name=\"" << XmlEscape(c.Name)
          << "\" time=\"" << Seconds(c.DurationMs) << "\"";
        if (c.Status == ReportStatus::Passed || c.Status == ReportStatus::None) {
          o << "/>\n";
        } else if (c.Status == ReportStatus::Skipped) {
          o << ">\n      <skipped message=\"" << XmlEscape(c.Message) << "\"/>\n    </testcase>\n";
        } else {
          const char* tag = (c.Status == ReportStatus::Error) ? "error" : "failure";
          o << ">\n      <" << tag << " message=\"" << XmlEscape(c.Message) << "\">"
            << XmlEscape(c.Stack) << "</" << tag << ">\n    </testcase>\n";
        }
      }
      o << "  </testsuite>\n";
    }
    o << "</testsuites>\n";
    return o.str();
  }

  std::string JsonText() const
  {
    std::ostringstream o;
    o << "{ \"testSuites\": [\n";
    const auto fixtures = FixturesInOrder();
    const std::string stamp = NowStamp();
    for (size_t i = 0; i < fixtures.size(); ++i) {
      const auto& fixture = fixtures[i];
      int ft = 0, ff = 0, fe = 0, fs = 0, fms = 0;
      for (const auto& c : FCases) {
        if (c.Fixture != fixture) continue;
        ++ft;
        fms += c.DurationMs;
        if (c.Status == ReportStatus::Failed || c.Status == ReportStatus::Timeout) ++ff;
        else if (c.Status == ReportStatus::Error) ++fe;
        else if (c.Status == ReportStatus::Skipped) ++fs;
      }
      if (i) o << ",\n";
      o << "  {\n";
      o << "    \"name\": \"" << JsonEscape(fixture) << "\", \"tests\": " << ft
        << ", \"failures\": " << ff << ", \"errors\": " << fe
        << ", \"skipped\": " << fs << ", \"duration\": " << Seconds(fms)
        << ", \"timestamp\": \"" << stamp << "\", \"testCases\": [";
      bool first = true;
      for (const auto& c : FCases) {
        if (c.Fixture != fixture) continue;
        if (!first) o << ",";
        first = false;
        o << "\n      { \"className\": \"" << JsonEscape(c.Fixture)
          << "\", \"testName\": \"" << JsonEscape(c.Name)
          << "\", \"duration\": " << Seconds(c.DurationMs)
          << ", \"status\": \"" << static_cast<int>(c.Status)
          << "\", \"errorMessage\": \"" << JsonEscape(c.Message) << "\" }";
      }
      o << " ] }";
    }
    o << "\n] }\n";
    return o.str();
  }

  std::string SonarXml() const
  {
    std::ostringstream o;
    o << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testExecutions version=\"1\">\n";
    std::vector<std::string> files;
    for (const auto& c : FCases) {
      bool seen = false;
      for (const auto& f : files)
        if (f == c.File) { seen = true; break; }
      if (!seen) files.push_back(c.File);
    }
    for (const auto& file : files) {
      o << "  <file path=\"" << XmlEscape(file) << "\">\n";
      for (const auto& c : FCases) {
        if (c.File != file) continue;
        o << "    <testCase name=\"" << XmlEscape(c.Fixture + "." + c.Name)
          << "\" duration=\"" << c.DurationMs << "\"";
        if (c.Status == ReportStatus::Passed || c.Status == ReportStatus::None) {
          o << "/>\n";
        } else {
          const char* tag = "failure";
          if (c.Status == ReportStatus::Skipped) tag = "skipped";
          else if (c.Status == ReportStatus::Error) tag = "error";
          o << ">\n      <" << tag << " message=\"" << XmlEscape(c.Message) << "\">"
            << XmlEscape(c.Stack) << "</" << tag << ">\n    </testCase>\n";
        }
      }
      o << "  </file>\n";
    }
    o << "</testExecutions>\n";
    return o.str();
  }

  std::string HtmlText() const
  {
    int passed = 0, failed = 0, skipped = 0;
    for (const auto& c : FCases) {
      if (c.Status == ReportStatus::Passed) ++passed;
      else if (c.Status == ReportStatus::Skipped) ++skipped;
      else if (c.Status != ReportStatus::None) ++failed;
    }
    std::ostringstream o;
    o << "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Dext Test Report</title></head><body>\n";
    o << "<h1>Dext Test Report</h1><p>Passed " << passed << " · Failed " << failed
      << " · Skipped " << skipped << "</p>\n<table>\n";
    for (const auto& c : FCases) {
      const char* label = "none";
      if (c.Status == ReportStatus::Passed) label = "passed";
      else if (c.Status == ReportStatus::Skipped) label = "skipped";
      else if (c.Status == ReportStatus::Error) label = "error";
      else if (c.Status != ReportStatus::None) label = "failed";
      o << "<tr><td>" << XmlEscape(c.Fixture) << "." << XmlEscape(c.Name)
        << "</td><td>" << label << "</td><td>" << c.DurationMs << " ms</td><td>"
        << XmlEscape(c.Message) << "</td></tr>\n";
    }
    o << "</table></body></html>\n";
    return o.str();
  }
};

inline ReportStatus ReportStatusFromType(const std::string& type)
{
  if (type == "Passed") return ReportStatus::Passed;
  if (type == "Failed") return ReportStatus::Failed;
  if (type == "Error") return ReportStatus::Error;
  if (type == "Ignored" || type == "Skipped") return ReportStatus::Skipped;
  return ReportStatus::None;
}

} // namespace Testing
} // namespace Dext

#endif
