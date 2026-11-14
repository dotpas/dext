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
{  Author:  Cesar Romero                                                    }
{  Created: 2026-11-14                                                      }
{                                                                           }
{  The identity map and the key of a tracked entity are built from the      }
{  primary key a query reads. A NUMBER column (Oracle) arrives as a TBcd:   }
{  its key string must tell one value from another, or every row of a       }
{  result is taken for the same entity.                                     }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.BcdKey.Tests;

interface

uses
  System.Rtti,
  System.SysUtils,
  System.Variants,
  Data.FmtBcd,
  Dext.Assertions,
  Dext.Entity.DbSet,
  Dext.Testing.Attributes;

type
  [TestFixture('Key string of a TBcd value (NUMBER column)')]
  TBcdKeyTests = class
  public
    [Test]
    [Description('Two different TBcd keys give two different key strings')]
    procedure Different_Bcd_Keys_Give_Different_Strings;

    [Test]
    [Description('A TBcd key gives the same string as the integer with the same value')]
    procedure Bcd_Key_Equals_The_Integer_Key;

    [Test]
    [Description('A TBcd with a fraction keeps it in the key string')]
    procedure Bcd_Key_Keeps_The_Fraction;

    [Test]
    [Description('The variant of a TBcd keeps its value')]
    procedure Bcd_To_Variant_Keeps_The_Value;

    [Test]
    [Description('A scalar read as TBcd (COUNT on Oracle) converts to an integer')]
    procedure Bcd_Scalar_Converts_To_Integer;

    [Test]
    [Description('A scalar that already is an integer converts as before')]
    procedure Integer_Scalar_Converts_To_Integer;
  end;

implementation

function Bcd(const AText: string): TValue;
begin
  Result := TValue.From<TBcd>(StrToBcd(AText, TFormatSettings.Invariant));
end;

procedure TBcdKeyTests.Different_Bcd_Keys_Give_Different_Strings;
begin
  Should(TValueToKeyString(Bcd('1')) <> TValueToKeyString(Bcd('2'))).BeTrue;
end;

procedure TBcdKeyTests.Bcd_Key_Equals_The_Integer_Key;
begin
  Should(TValueToKeyString(Bcd('42'))).Be(TValueToKeyString(TValue.From<Integer>(42)));
end;

procedure TBcdKeyTests.Bcd_Key_Keeps_The_Fraction;
begin
  Should(TValueToKeyString(Bcd('1.5')) <> TValueToKeyString(Bcd('1'))).BeTrue;
end;

procedure TBcdKeyTests.Bcd_To_Variant_Keeps_The_Value;
begin
  Should(VarToStr(TValueToVariant(Bcd('7'))) = '7').BeTrue;
end;

procedure TBcdKeyTests.Bcd_Scalar_Converts_To_Integer;
begin
  Should(TValueToInteger(Bcd('3'))).Be(3);
end;

procedure TBcdKeyTests.Integer_Scalar_Converts_To_Integer;
begin
  Should(TValueToInteger(TValue.From<Integer>(5))).Be(5);
  Should(TValueToInteger(TValue.From<Int64>(6))).Be(6);
end;

end.
