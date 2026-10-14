unit Dext.Json.RecordFieldNames.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types;

type
  TJsonFieldNamesRecord = record
    Flag: Integer;
    Fattura: string;
    Format: string;
    FName: string;
    FValue: Integer;
    F_Note: string;
    Data: Integer;
  end;

  [TestFixture('JSON - SmartRecordMapping strips only the backing-field F (#261)')]
  TJsonRecordFieldNamesTests = class
  public
    [Test('The rule: F plus an uppercase letter or _ loses the F, any other name stays')]
    procedure Rule_SmartRecordFieldName;
    [Test('Writing: Flag, Fattura, Format keep their names; FName becomes Name')]
    procedure Record_Writes;
    [Test('Reading: the right keys fill the fields, nothing is lost')]
    procedure Record_Reads;
    [Test('Round trip: what is written is read back')]
    procedure Record_RoundTrip;
    [Test('SmartRecordMapping off: every field keeps its name')]
    procedure Record_SmartMappingOff;
  end;

implementation

function Sample: TJsonFieldNamesRecord;
begin
  Result.Flag := 1;
  Result.Fattura := 'F-12';
  Result.Format := 'A4';
  Result.FName := 'Rossi';
  Result.FValue := 7;
  Result.F_Note := 'n';
  Result.Data := 5;
end;

procedure TJsonRecordFieldNamesTests.Rule_SmartRecordFieldName;
begin
  Should(TJsonUtils.SmartRecordFieldName('FName')).Be('Name');
  Should(TJsonUtils.SmartRecordFieldName('FValue')).Be('Value');
  Should(TJsonUtils.SmartRecordFieldName('F_Note')).Be('_Note');
  Should(TJsonUtils.SmartRecordFieldName('Flag')).Be('Flag');
  Should(TJsonUtils.SmartRecordFieldName('Fattura')).Be('Fattura');
  Should(TJsonUtils.SmartRecordFieldName('Format')).Be('Format');
  Should(TJsonUtils.SmartRecordFieldName('F')).Be('F');
  Should(TJsonUtils.SmartRecordFieldName('Data')).Be('Data');
end;

procedure TJsonRecordFieldNamesTests.Record_Writes;
begin
  Should(TDextJson.Serialize(Sample)).Be('{"Flag":1,"Fattura":"F-12","Format":"A4",' +
    '"Name":"Rossi","Value":7,"_Note":"n","Data":5}');
end;

procedure TJsonRecordFieldNamesTests.Record_Reads;
var
  R: TJsonFieldNamesRecord;
begin
  R := TDextJson.Deserialize<TJsonFieldNamesRecord>('{"Flag":7,"Fattura":"F-99",' +
    '"Format":"A3","Name":"Bianchi","Value":8,"_Note":"m","Data":6}');
  Should(R.Flag).Be(7);
  Should(R.Fattura).Be('F-99');
  Should(R.Format).Be('A3');
  Should(R.FName).Be('Bianchi');
  Should(R.FValue).Be(8);
  Should(R.F_Note).Be('m');
  Should(R.Data).Be(6);
end;

procedure TJsonRecordFieldNamesTests.Record_RoundTrip;
var
  R: TJsonFieldNamesRecord;
begin
  R := TDextJson.Deserialize<TJsonFieldNamesRecord>(TDextJson.Serialize(Sample));
  Should(R.Flag).Be(1);
  Should(R.Fattura).Be('F-12');
  Should(R.Format).Be('A4');
  Should(R.FName).Be('Rossi');
  Should(R.FValue).Be(7);
  Should(R.F_Note).Be('n');
  Should(R.Data).Be(5);
end;

procedure TJsonRecordFieldNamesTests.Record_SmartMappingOff;
var
  Settings: TJsonSettings;
  R: TJsonFieldNamesRecord;
begin
  Settings := TJsonSettings.Default.SmartRecordMapping(False);
  Should(TDextJson.Serialize(Sample, Settings)).Be('{"Flag":1,"Fattura":"F-12",' +
    '"Format":"A4","FName":"Rossi","FValue":7,"F_Note":"n","Data":5}');
  R := TDextJson.Deserialize<TJsonFieldNamesRecord>('{"Flag":7,"FName":"Bianchi"}',
    Settings);
  Should(R.Flag).Be(7);
  Should(R.FName).Be('Bianchi');
end;

end.
