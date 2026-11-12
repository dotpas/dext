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
{                                                                           }
{  Tests of the http.sys object pools (requests, responses, buffers): the   }
{  spin lock runs without thread tracking, a full pool frees the object     }
{  outside the lock, and a pool with room keeps the object for the next     }
{  Acquire. No http.sys queue is needed.                                    }
{                                                                           }
{***************************************************************************}
unit Dext.Server.HttpSys.Pools.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Rtti,
  Dext.Testing,
  Dext.Testing.Fluent,
  Dext.Server.HttpSys;

type
  [TestFixture('Dext.Server http.sys pools (spin lock and Release)')]
  THttpSysPoolsTests = class
  public
    [Test]
    procedure BufferPool_SpinLockWithoutThreadTracking;
    [Test]
    procedure RequestPool_SpinLockWithoutThreadTracking;
    [Test]
    procedure ResponsePool_SpinLockWithoutThreadTracking;
    [Test]
    procedure BufferPool_Full_FreesOutsideTheLock;
    [Test]
    procedure BufferPool_WithRoom_KeepsTheBuffer;
  end;

implementation

type
  /// A buffer that, when freed, records whether the pool lock was held.
  TWatchedBuffer = class(TMemoryStream)
  public
    destructor Destroy; override;
  end;

var
  WatchedPool: TObject;
  FreedWithLockHeld: Integer; // -1 = not freed, 0 = lock free, 1 = lock held

function PoolLock(APool: TObject): TSpinLock;
var
  Ctx: TRttiContext;
  Field: TRttiField;
begin
  Field := Ctx.GetType(APool.ClassType).GetField('FLock');
  if Field = nil then
    raise Exception.Create('FLock not found on ' + APool.ClassName);
  Result := Field.GetValue(APool).AsType<TSpinLock>;
end;

destructor TWatchedBuffer.Destroy;
begin
  if WatchedPool <> nil then
  begin
    if PoolLock(WatchedPool).IsLocked then
      FreedWithLockHeld := 1
    else
      FreedWithLockHeld := 0;
  end;
  inherited;
end;

{ THttpSysPoolsTests }

procedure THttpSysPoolsTests.BufferPool_SpinLockWithoutThreadTracking;
var
  Pool: TDextHttpSysBufferPool;
begin
  Pool := TDextHttpSysBufferPool.Create;
  try
    Should(PoolLock(Pool).IsThreadTrackingEnabled).BeFalse;
  finally
    Pool.Free;
  end;
end;

procedure THttpSysPoolsTests.RequestPool_SpinLockWithoutThreadTracking;
var
  Pool: TDextHttpSysRequestPool;
begin
  Pool := TDextHttpSysRequestPool.Create;
  try
    Should(PoolLock(Pool).IsThreadTrackingEnabled).BeFalse;
  finally
    Pool.Free;
  end;
end;

procedure THttpSysPoolsTests.ResponsePool_SpinLockWithoutThreadTracking;
var
  Pool: TDextHttpSysResponsePool;
begin
  Pool := TDextHttpSysResponsePool.Create;
  try
    Should(PoolLock(Pool).IsThreadTrackingEnabled).BeFalse;
  finally
    Pool.Free;
  end;
end;

procedure THttpSysPoolsTests.BufferPool_Full_FreesOutsideTheLock;
var
  Pool: TDextHttpSysBufferPool;
begin
  // A pool with no room: Release frees the buffer
  Pool := TDextHttpSysBufferPool.Create(0);
  try
    WatchedPool := Pool;
    FreedWithLockHeld := -1;
    Pool.Release(TWatchedBuffer.Create);
    Should(FreedWithLockHeld).Be(0);
  finally
    WatchedPool := nil;
    Pool.Free;
  end;
end;

procedure THttpSysPoolsTests.BufferPool_WithRoom_KeepsTheBuffer;
var
  Pool: TDextHttpSysBufferPool;
  Buffer, Again: TMemoryStream;
begin
  Pool := TDextHttpSysBufferPool.Create(1);
  try
    Buffer := TWatchedBuffer.Create;
    Buffer.Size := 100000;
    Buffer.Position := 10;
    FreedWithLockHeld := -1;
    Pool.Release(Buffer);
    Should(FreedWithLockHeld).Be(-1);
    Again := Pool.Acquire;
    try
      Should(Again = Buffer).BeTrue;
      Should(Again.Position).Be(0);
      Should(Again.Size).Be(65536);
    finally
      Again.Free;
    end;
  finally
    Pool.Free;
  end;
end;

end.
