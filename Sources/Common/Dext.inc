{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Global Configuration & Compiler Directives                      }
{                                                                           }
{***************************************************************************}

{$IFNDEF DEXT_INC}
{$DEFINE DEXT_INC}

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

//---------------------------------------------------------------------------
// Delphi Version Detection (Industry Standard Pattern)
//---------------------------------------------------------------------------

{$IFDEF VER290} {$DEFINE DEXT_DELPHIXE8_UP}    {$ENDIF} // XE8
{$IFDEF VER300} {$DEFINE DEXT_DELPHI10_UP}     {$ENDIF} // 10 Seattle
{$IFDEF VER310} {$DEFINE DEXT_DELPHI101_UP}    {$ENDIF} // 10.1 Berlin
{$IFDEF VER320} {$DEFINE DEXT_DELPHI102_UP}    {$ENDIF} // 10.2 Tokyo
{$IFDEF VER330} {$DEFINE DEXT_DELPHI103_UP}    {$ENDIF} // 10.3 Rio
{$IFDEF VER340} {$DEFINE DEXT_DELPHI104_UP}    {$ENDIF} // 10.4 Sydney
{$IFDEF VER350} {$DEFINE DEXT_DELPHI11_UP}     {$ENDIF} // 11 Alexandria
{$IFDEF VER360} {$DEFINE DEXT_DELPHI12_UP}     {$ENDIF} // 12 Athens
{$IFDEF VER370} {$DEFINE DEXT_DELPHI13_UP}     {$ENDIF} // 13 Athens (Next)

// Accumulate "UP" flags for easier checking
{$IFDEF DEXT_DELPHI13_UP}  {$DEFINE DEXT_DELPHI12_UP}  {$ENDIF}
{$IFDEF DEXT_DELPHI12_UP}  {$DEFINE DEXT_DELPHI11_UP}  {$ENDIF}
{$IFDEF DEXT_DELPHI11_UP}  {$DEFINE DEXT_DELPHI104_UP} {$ENDIF}
{$IFDEF DEXT_DELPHI104_UP} {$DEFINE DEXT_DELPHI103_UP} {$ENDIF}
{$IFDEF DEXT_DELPHI103_UP} {$DEFINE DEXT_DELPHI102_UP} {$ENDIF}
{$IFDEF DEXT_DELPHI102_UP} {$DEFINE DEXT_DELPHI101_UP} {$ENDIF}
{$IFDEF DEXT_DELPHI101_UP} {$DEFINE DEXT_DELPHI10_UP}  {$ENDIF}
{$IFDEF DEXT_DELPHI10_UP}  {$DEFINE DEXT_DELPHIXE8_UP} {$ENDIF}

//---------------------------------------------------------------------------
// Compiler Features
//---------------------------------------------------------------------------

// System.Hash unit (Introduced in Delphi XE8)
{$IFDEF DEXT_DELPHIXE8_UP}
  {$DEFINE DEXT_HAS_SYSTEM_HASH}
  {$DEFINE DEXT_HAS_NETHTTP}
{$ENDIF}

// Parallel Programming Library (Introduced in Delphi XE7)
{$IFDEF VER280} {$DEFINE DEXT_HAS_PPL} {$ENDIF} // XE7
{$IFDEF DEXT_DELPHIXE8_UP} {$DEFINE DEXT_HAS_PPL} {$ENDIF}

// [Weak] Attribute (Introduced for all platforms in Delphi 10.1 Berlin)
{$IFDEF DEXT_DELPHI101_UP}
  {$DEFINE DEXT_HAS_WEAK}
{$ENDIF}

// Web Stencils support (Introduced in Delphi 12.2 - MSWindows only)
{$IFDEF DEXT_DELPHI12_UP}
  {$IFDEF MSWINDOWS}
    {.$DEFINE DEXT_ENABLE_WEB_STENCILS}
  {$ENDIF}
{$ENDIF}

//---------------------------------------------------------------------------
// User Overrides
//---------------------------------------------------------------------------

// Define DEXT_FORCE_INDY_HASH in your project options or here
// to force usage of Indy for hashing even on newer Delphi versions.
{$IFDEF DEXT_FORCE_INDY_HASH}
  {$UNDEF DEXT_HAS_SYSTEM_HASH}
{$ENDIF}

// Native OpenSSL 3.x (Dext.Net.Security.OpenSSL) and Indy HTTPS.
// Disabled by default so Linux64 installs via TMS Smart Setup do not require
// libssl-dev in the RAD Studio SDK cache (ld-linux: cannot find -lcrypto / -lssl).
// Uncomment to enable HTTPS, Redis TLS, and the native epoll TLS engine, then rebuild.
// Windows runtime: libssl-3.dll + libcrypto-3.dll next to the executable.
// Linux: install libssl-dev on the PAServer machine, then SDK Manager >
// Update Local File Cache so libssl.so and libcrypto.so exist in the SDK.
{.$DEFINE DEXT_ENABLE_SSL}
// Define DEXT_ENABLE_TAURUS_TLS to enable Taurus TLS support (OpenSSL 1.1.x / 3.x)
{.$DEFINE DEXT_ENABLE_TAURUS_TLS}

// Define DEXT_ENABLE_DCS to enable the DCS (Delphi-Cross-Socket) server adapter.
// Note: Requires the DCS library in the project search path.
//       https://github.com/winddriver/Delphi-Cross-Socket
{.$DEFINE DEXT_ENABLE_DCS}

//---------------------------------------------------------------------------
// Modules & Components
//---------------------------------------------------------------------------

// Enable/Disable Dext.Entity (ORM & Database support)
{$DEFINE DEXT_ENABLE_ENTITY}

// Enable/Disable the IDE Sidecar Expert (project monitoring, unit test sync,
// and the "Dext Sidecar" menu in the IDE). Disabled by default until the
// feature is stable. Uncomment to activate.
{.$DEFINE DEXT_ENABLE_SIDECAR_EXPERT}

//---------------------------------------------------------------------------
// Database Drivers
//---------------------------------------------------------------------------

{$IFDEF DEXT_ENABLE_ENTITY}
  {.$DEFINE DEXT_USE_ENTITY_PREFIX}
  // Enable/Disable specific database drivers to avoid unnecessary dependencies.
  // Useful for Delphi Professional/Community editions.
  // ---------------------------------------------------------------------------
  // Standard Drivers
  {$DEFINE DEXT_ENABLE_DB_SQLITE}
  // Enable SQLite JSON functions (requires sqlite3.dll compiled with SQLITE_ENABLE_JSON1)
  {$IFDEF DEXT_ENABLE_DB_SQLITE}
    {$DEFINE DEXT_ENABLE_SQLITE_JSON}
  {$ENDIF}
  {.$DEFINE DEXT_ENABLE_DB_POSTGRES}
  {.$DEFINE DEXT_ENABLE_DB_MYSQL}
  {.$DEFINE DEXT_ENABLE_DB_MSSQL}
  {.$DEFINE DEXT_ENABLE_DB_ORACLE}
  {.$DEFINE DEXT_ENABLE_DB_FIREBIRD}
  {.$DEFINE DEXT_ENABLE_DB_IB}          // InterBase
  {.$DEFINE DEXT_ENABLE_DB_ODBC}

  // Enterprise / Additional Drivers (need testing)
  {.$DEFINE DEXT_ENABLE_DB_ADS}         // Advantage Database Server
  {.$DEFINE DEXT_ENABLE_DB_ASA}         // SQL Anywhere
  {.$DEFINE DEXT_ENABLE_DB_DB2}         // IBM DB2
  {.$DEFINE DEXT_ENABLE_DB_DS}          // DataSnap
  {.$DEFINE DEXT_ENABLE_DB_INFX}        // Informix
  {.$DEFINE DEXT_ENABLE_DB_MONGODB}     // MongoDB
  {.$DEFINE DEXT_ENABLE_DB_MSACC}       // MS Access
  {.$DEFINE DEXT_ENABLE_DB_TERADATA}    // Teradata
{$ENDIF}
{$ENDIF} // close {$IFNDEF DEXT_INC}
