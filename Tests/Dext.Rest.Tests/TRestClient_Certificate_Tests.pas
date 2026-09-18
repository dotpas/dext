{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
unit TRestClient_Certificate_Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Testing,
  Dext.Testing.Fluent,
  Dext.Net.Engine,
  Dext.Net.RestClient;

type
  [TestFixture('TRestClient Client Certificate Tests')]
  TRestClientCertificateTests = class
  public
    [Test]
    procedure FluentApi_ShouldAcceptFilePathAndConfigureClient;
    [Test]
    procedure FluentApi_ShouldAcceptStreamAndConfigureClient;
    [Test]
    procedure Engine_SetAndClearClientCertificate_ShouldNotLeakOrThrow;
    [Test]
    procedure Engine_SetFromStream_ShouldCloneContentIndependently;
  end;

implementation

{ TRestClientCertificateTests }

procedure TRestClientCertificateTests.FluentApi_ShouldAcceptFilePathAndConfigureClient;
var
  Client: TRestClient;
begin
  Client := RestClient('https://example.com')
    .ClientCertificate('cert.pfx', 'password123');

  Should(Assigned(Client.Instance)).BeTrue;
end;

procedure TRestClientCertificateTests.FluentApi_ShouldAcceptStreamAndConfigureClient;
var
  Client: TRestClient;
  CertStream: TMemoryStream;
  DummyBytes: TBytes;
begin
  CertStream := TMemoryStream.Create;
  try
    DummyBytes := TBytes.Create($30, $82, $01, $00);
    CertStream.WriteBuffer(DummyBytes[0], Length(DummyBytes));
    CertStream.Position := 0;

    Client := RestClient('https://example.com')
      .ClientCertificate(CertStream, 'password123');

    Should(Assigned(Client.Instance)).BeTrue;
  finally
    CertStream.Free;
  end;
end;

procedure TRestClientCertificateTests.Engine_SetAndClearClientCertificate_ShouldNotLeakOrThrow;
var
  Engine: IDextHttpEngine;
  CertStream: TMemoryStream;
  DummyBytes: TBytes;
begin
  Engine := CreateHttpEngine;
  Should(Assigned(Engine)).BeTrue;

  // File overload
  Engine.SetClientCertificate('cert.pfx', 'secret');
  Engine.ClearClientCertificate;

  // Stream overload
  CertStream := TMemoryStream.Create;
  try
    DummyBytes := TBytes.Create($01, $02, $03, $04);
    CertStream.WriteBuffer(DummyBytes[0], Length(DummyBytes));
    CertStream.Position := 0;

    Engine.SetClientCertificate(CertStream, 'secret');
    Engine.ClearClientCertificate;
  finally
    CertStream.Free;
  end;
end;

procedure TRestClientCertificateTests.Engine_SetFromStream_ShouldCloneContentIndependently;
var
  Engine: IDextHttpEngine;
  CertStream: TMemoryStream;
  DummyBytes: TBytes;
begin
  Engine := CreateHttpEngine;
  CertStream := TMemoryStream.Create;
  try
    DummyBytes := TBytes.Create($AA, $BB, $CC, $DD);
    CertStream.WriteBuffer(DummyBytes[0], Length(DummyBytes));
    CertStream.Position := 0;

    Engine.SetClientCertificate(CertStream, 'password');
  finally
    // Free caller stream immediately to prove engine copied it safely
    CertStream.Free;
  end;

  // Clear safely after caller stream is gone
  Engine.ClearClientCertificate;
end;

end.
