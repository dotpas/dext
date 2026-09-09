{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Graph - Orquestração de agentes estilo LangGraph        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    Checkpointers em memória (MemorySaver) e em arquivo JSON.              }
{                                                                           }
{***************************************************************************}
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the LICENSE is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
unit Dext.AI.Graph.Checkpointer;

interface

uses
  Dext.AI.Graph.Contracts,
  Dext.Collections,
  Dext.Collections.Dict,
  System.SysUtils,
  System.SyncObjs,
  System.Hash;

type
  /// <summary>
  /// In-memory checkpointer. FLock serializes Save/Load/Exists/Delete
  /// across threads of the same process - TDictionary from Dext.Collections
  /// is not thread-safe on its own, and MCP tools/HTTP handlers routinely
  /// call into the same TAgentGraph from multiple worker threads.
  /// </summary>
  TMemoryCheckpointer = class(TInterfacedObject, ICheckpointer)
  private
    FStore: TDictionary<string, string>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Save(const AThreadId: string; const AStateJson: string);
    function  Load(const AThreadId: string): string;
    function  Exists(const AThreadId: string): Boolean;
    procedure Delete(const AThreadId: string);
  end;

  /// <summary>
  /// File-based checkpointer. FLock serializes access within this process;
  /// Save writes to a uniquely-named temp file and then replaces the final
  /// file, so a crash or a concurrent Save from another thread never leaves
  /// a truncated/interleaved checkpoint on disk. Does not coordinate across
  /// separate OS processes sharing the same ABasePath.
  /// </summary>
  TFileCheckpointer = class(TInterfacedObject, ICheckpointer)
  private
    FBasePath: string;
    FLock: TCriticalSection;
    function FilePath(const AThreadId: string): string;
    function SanitizeId(const AThreadId: string): string;
  public
    constructor Create(const ABasePath: string = '');
    destructor Destroy; override;
    procedure Save(const AThreadId: string; const AStateJson: string);
    function  Load(const AThreadId: string): string;
    function  Exists(const AThreadId: string): Boolean;
    procedure Delete(const AThreadId: string);
  end;

implementation

uses
  System.IOUtils;

{ TMemoryCheckpointer }

constructor TMemoryCheckpointer.Create;
begin
  inherited Create;
  FStore := TDictionary<string, string>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TMemoryCheckpointer.Destroy;
begin
  FLock.Free;
  FStore.Free;
  inherited;
end;

procedure TMemoryCheckpointer.Save(const AThreadId: string; const AStateJson: string);
begin
  FLock.Enter;
  try
    FStore.AddOrSetValue(AThreadId, AStateJson);
  finally
    FLock.Leave;
  end;
end;

function TMemoryCheckpointer.Load(const AThreadId: string): string;
begin
  FLock.Enter;
  try
    if not FStore.TryGetValue(AThreadId, Result) then
      raise EGraphError.CreateFmt('Checkpoint não encontrado: %s', [AThreadId]);
  finally
    FLock.Leave;
  end;
end;

function TMemoryCheckpointer.Exists(const AThreadId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FStore.ContainsKey(AThreadId);
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryCheckpointer.Delete(const AThreadId: string);
begin
  FLock.Enter;
  try
    FStore.Remove(AThreadId);
  finally
    FLock.Leave;
  end;
end;

{ TFileCheckpointer }

constructor TFileCheckpointer.Create(const ABasePath: string);
begin
  inherited Create;
  if ABasePath = '' then
    FBasePath := TPath.Combine(TPath.GetTempPath, 'dext-ai-graph')
  else
    FBasePath := ABasePath;
  FLock := TCriticalSection.Create;
end;

destructor TFileCheckpointer.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TFileCheckpointer.SanitizeId(const AThreadId: string): string;
var
  I: Integer;
  C: Char;
  Clean: string;
begin
  Clean := '';
  for I := 1 to Length(AThreadId) do
  begin
    C := AThreadId[I];
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Clean := Clean + C
    else
      Clean := Clean + '_';
  end;
  if Clean = '' then
    Clean := 'thread';
  // Substituir caracteres inválidos por "_" pode colidir (ex.: "a/b" e "a:b"
  // viram ambos "a_b"), fazendo threads distintas compartilharem o mesmo
  // arquivo de checkpoint. Um sufixo hash do id original torna o nome do
  // arquivo praticamente único mesmo quando a parte legível colide.
  Result := Clean + '-' + IntToHex(THashBobJenkins.GetHashValue(AThreadId), 8);
end;

function TFileCheckpointer.FilePath(const AThreadId: string): string;
begin
  Result := TPath.Combine(FBasePath, SanitizeId(AThreadId) + '.json');
end;

procedure TFileCheckpointer.Save(const AThreadId: string; const AStateJson: string);
var
  FinalPath, TempPath: string;
begin
  FLock.Enter;
  try
    TDirectory.CreateDirectory(FBasePath);
    FinalPath := FilePath(AThreadId);
    // Escreve num arquivo temporário com nome único e só então substitui o
    // definitivo (delete-then-move) - evita deixar um checkpoint truncado
    // no disco se o processo morrer no meio da escrita, e evita que duas
    // Saves da mesma thread id (em teoria impedidas pelo FLock, mas também
    // seguro se chamado de fora) produzam um arquivo com bytes intercalados.
    TempPath := FinalPath + '.tmp-' +
      TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
    TFile.WriteAllText(TempPath, AStateJson, TEncoding.UTF8);
    try
      if TFile.Exists(FinalPath) then
        TFile.Delete(FinalPath);
      TFile.Move(TempPath, FinalPath);
    except
      if TFile.Exists(TempPath) then
        TFile.Delete(TempPath);
      raise;
    end;
  finally
    FLock.Leave;
  end;
end;

function TFileCheckpointer.Load(const AThreadId: string): string;
var
  Path: string;
begin
  FLock.Enter;
  try
    Path := FilePath(AThreadId);
    if not TFile.Exists(Path) then
      raise EGraphError.CreateFmt('Checkpoint não encontrado: %s', [AThreadId]);
    Result := TFile.ReadAllText(Path, TEncoding.UTF8);
  finally
    FLock.Leave;
  end;
end;

function TFileCheckpointer.Exists(const AThreadId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := TFile.Exists(FilePath(AThreadId));
  finally
    FLock.Leave;
  end;
end;

procedure TFileCheckpointer.Delete(const AThreadId: string);
var
  Path: string;
begin
  FLock.Enter;
  try
    Path := FilePath(AThreadId);
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  finally
    FLock.Leave;
  end;
end;

end.
