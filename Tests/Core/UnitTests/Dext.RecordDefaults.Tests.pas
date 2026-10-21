unit Dext.RecordDefaults.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json.Types,
  Dext.Net.Security;

type
  // TJsonSettings.Default and TDextTLSOptions.DefaultClient/DefaultServer return a record
  // with managed fields. Result is storage the caller already initialized, so it must be
  // finalized before it is zeroed: otherwise the strings it held are never released.
  [TestFixture('Record defaults - TJsonSettings and TDextTLSOptions release what they replace')]
  TRecordDefaultsTests = class
  public
    [Test('TJsonSettings.Default releases the default DateFormat of the settings it replaces')]
    procedure JsonSettings_Default_ReleasesTheDefaultDateFormat;
    [Test('TJsonSettings.Default releases a custom DateFormat of the settings it replaces')]
    procedure JsonSettings_Default_ReleasesACustomDateFormat;
    [Test('TDextTLSOptions.DefaultClient releases the strings of the options it replaces')]
    procedure TlsOptions_DefaultClient_ReleasesTheStrings;
    [Test('TDextTLSOptions.DefaultServer releases the strings of the options it replaces')]
    procedure TlsOptions_DefaultServer_ReleasesTheStrings;
    [Test('TDextTLSOptions.DefaultServer can take its files from the options it replaces')]
    procedure TlsOptions_DefaultServer_ArgumentsFromTheSameVariable;
  end;

implementation

// A string built at run time, so that its reference count starts at 1
function RuntimeText(const APrefix: string): string;
begin
  Result := APrefix + IntToStr(Random(1) + 1234567) + '-abcdefghijklmnopqrstuvwxyz';
end;

{ TRecordDefaultsTests }

procedure TRecordDefaultsTests.JsonSettings_Default_ReleasesTheDefaultDateFormat;
var
  S: TJsonSettings;
  Held: string;
begin
  S := TJsonSettings.Default;
  Held := S.DateFormat;
  S := TJsonSettings.Default;
  // 1: only Held keeps it. -1: a constant, nothing to release. 2: the old one was leaked.
  Should((StringRefCount(Held) = 1) or (StringRefCount(Held) = -1)).BeTrue;
  Should(S.DateFormat).Be('yyyy-mm-dd"T"hh:nn:ss.zzz');
end;

procedure TRecordDefaultsTests.JsonSettings_Default_ReleasesACustomDateFormat;
var
  S: TJsonSettings;
  Format: string;
begin
  Format := RuntimeText('yyyy-mm-dd');
  S := TJsonSettings.Default.CustomDateFormat(Format);
  Should(StringRefCount(Format)).Be(2);
  S := TJsonSettings.Default;
  Should(StringRefCount(Format)).Be(1);
end;

procedure TRecordDefaultsTests.TlsOptions_DefaultClient_ReleasesTheStrings;
var
  O: TDextTLSOptions;
  Cert: string;
begin
  O := TDextTLSOptions.DefaultClient;
  Cert := RuntimeText('client-');
  O.CertFile := Cert;
  Should(StringRefCount(Cert)).Be(2);
  O := TDextTLSOptions.DefaultClient;
  Should(StringRefCount(Cert)).Be(1);
  Should(O.CertFile).Be('');
  Should(O.Provider).Be('Auto');
end;

procedure TRecordDefaultsTests.TlsOptions_DefaultServer_ReleasesTheStrings;
var
  O: TDextTLSOptions;
  OldCert, NewCert, NewKey: string;
begin
  OldCert := RuntimeText('old-cert-');
  O := TDextTLSOptions.DefaultServer(OldCert, RuntimeText('old-key-'));
  Should(StringRefCount(OldCert)).Be(2);
  NewCert := RuntimeText('new-cert-');
  NewKey := RuntimeText('new-key-');
  O := TDextTLSOptions.DefaultServer(NewCert, NewKey);
  Should(StringRefCount(OldCert)).Be(1);
  Should(O.CertFile).Be(NewCert);
  Should(O.KeyFile).Be(NewKey);
end;

// In a routine of its own, so that the temporaries of the call are released on exit
procedure ServerFromItself(var AOptions: TDextTLSOptions);
begin
  AOptions := TDextTLSOptions.DefaultServer(AOptions.CertFile, AOptions.KeyFile);
end;

procedure TRecordDefaultsTests.TlsOptions_DefaultServer_ArgumentsFromTheSameVariable;
var
  O: TDextTLSOptions;
  Cert, Key: string;
  Count: Integer;
begin
  // The const arguments point into O. Finalizing Result must not release them before
  // they are read, whatever storage the compiler passes as Result.
  Cert := RuntimeText('cert-');
  Key := RuntimeText('key-');
  O := TDextTLSOptions.DefaultServer(Cert, Key);
  Cert := '';
  Key := '';
  ServerFromItself(O);
  Count := StringRefCount(O.CertFile);
  Should(Count).Be(1);
  Should(O.CertFile).StartWith('cert-');
  Should(O.KeyFile).StartWith('key-');
end;

end.
