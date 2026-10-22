{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
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
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2026-10-22                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Testing.Coverage.Lcov.Tests;

interface

uses
  Dext.Testing.Attributes;

type
  /// <summary>Parser for the LCOV trace that llvm-cov writes on Win64x.</summary>
  [TestFixture('LCOV parser')]
  TLcovParserTests = class
  public
    [Test]
    procedure ShouldReadHitsAndUncoveredLines;

    [Test]
    procedure ShouldIgnoreDaBeforeSourceFile;

    [Test]
    procedure ShouldKeepTwoFilesAndSkipBlankRecords;

    [Test]
    procedure ShouldReturnEmptyWhenFileIsMissing;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Dext.Assertions,
  Dext.Testing.Coverage.Lcov;

procedure TLcovParserTests.ShouldReadHitsAndUncoveredLines;
var
  Files: TArray<TLcovFile>;
begin
  Files := ParseLcov(
    'SF:C:\src\Smoke.cpp'#13#10 +
    'DA:14,1'#13#10 +
    'DA:23,0'#13#10 +
    'DA:0,4'#13#10 +
    'end_of_record'#13#10);
  Should(Length(Files)).Be(1);
  Should(Files[0].Path).Be('C:\src\Smoke.cpp');
  Should(Length(Files[0].Lines)).Be(2);
  Should(Files[0].Lines[0].Line).Be(14);
  Should(Files[0].Lines[0].Hits).Be(1);
  Should(Files[0].Lines[1].Line).Be(23);
  Should(Files[0].Lines[1].Hits).Be(0);
end;

procedure TLcovParserTests.ShouldIgnoreDaBeforeSourceFile;
var
  Files: TArray<TLcovFile>;
begin
  Files := ParseLcov(
    'DA:10,1'#10 +
    'SF:'#10 +
    'DA:4,1'#10 +
    'SF:other.cpp'#10 +
    'DA:2,3'#10);
  Should(Length(Files)).Be(1);
  Should(Files[0].Path).Be('other.cpp');
  Should(Length(Files[0].Lines)).Be(1);
  Should(Files[0].Lines[0].Line).Be(2);
  Should(Files[0].Lines[0].Hits).Be(3);
end;

procedure TLcovParserTests.ShouldKeepTwoFilesAndSkipBlankRecords;
var
  Files: TArray<TLcovFile>;
begin
  Files := ParseLcov(
    #13#10 +
    'SF:a.cpp'#10 +
    'BRDA:1,0,0,1'#10 +
    'DA:1,2'#10 +
    'end_of_record'#10 +
    #10 +
    'SF:b.cpp'#10 +
    'DA:8,0'#10 +
    'end_of_record'#10);
  Should(Length(Files)).Be(2);
  Should(Files[0].Path).Be('a.cpp');
  Should(Files[0].Lines[0].Hits).Be(2);
  Should(Files[1].Path).Be('b.cpp');
  Should(Files[1].Lines[0].Line).Be(8);
  Should(Files[1].Lines[0].Hits).Be(0);
end;

procedure TLcovParserTests.ShouldReturnEmptyWhenFileIsMissing;
var
  Path: string;
  Files: TArray<TLcovFile>;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'dext-lcov-missing.info');
  if TFile.Exists(Path) then
    TFile.Delete(Path);
  Files := ParseLcovFile(Path);
  Should(Length(Files)).Be(0);

  Path := TPath.Combine(TPath.GetTempPath, 'dext-lcov-sample.info');
  try
    TFile.WriteAllText(Path, 'SF:sample.cpp'#10'DA:9,1'#10'end_of_record'#10);
    Files := ParseLcovFile(Path);
    Should(Length(Files)).Be(1);
    Should(Files[0].Path).Be('sample.cpp');
    Should(Files[0].Lines[0].Line).Be(9);
    Should(Files[0].Lines[0].Hits).Be(1);
  finally
    if TFile.Exists(Path) then
      TFile.Delete(Path);
  end;
end;

end.
