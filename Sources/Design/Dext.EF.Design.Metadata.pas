unit Dext.EF.Design.Metadata;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Collections,
  Dext.Collections.Base,
  Dext.Entity.Core,
  Dext.Entity.DataProvider,
  Dext.Entity.Metadata;
  
/// <summary>
///   Design-time helper to refresh metadata from source code using the canonical parser.
/// </summary>
procedure RefreshProviderMetadata(AProvider: TEntityDataProvider);

implementation

uses
  System.IOUtils,
  System.Types,
  Winapi.Windows;

procedure RefreshProviderMetadata(AProvider: TEntityDataProvider);
var
  FileName, Content: string;
  MD: TEntityClassMetadata;
  ParsedList: IList<TEntityClassMetadata>;
  Parser: TEntityMetadataParser;
  Missing: TArray<string>;
begin
  if AProvider = nil then
    Exit;

  AProvider.ClearMetadata;
  Missing := nil;
  Parser := TEntityMetadataParser.Create;
  try
    for FileName in AProvider.ModelUnits do
    begin
      Content := '';
      if Assigned(GOnGetSourceContent) then
        Content := GOnGetSourceContent(FileName);

      // No source from the IDE and no file on disk: the parser would return
      // an empty list and the unit would silently count as "no entities".
      if (Content = '') and not FileExists(FileName) then
        Missing := Missing + [FileName];

      // AddOrSetMetadata copies each item into the provider, so the parsed
      // list keeps the ownership of its own objects and frees them.
      ParsedList := Parser.ParseUnit(FileName, Content);
      for MD in ParsedList do
        AProvider.AddOrSetMetadata(MD);
    end;
  finally
    Parser.Free;
  end;

  AProvider.UpdateRefreshSummary(Missing);
end;

end.
