unit Dext.Web.JsonIgnoreBinding.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Json,
  Dext.Web.ModelBinding;

type
  /// A class bound from the request body.
  TIgnoreBodyClass = class
  private
    FCode: string;
    FInternal: string;
    FPassword: string;
    FTotal: Integer;
  public
    property Code: string read FCode write FCode;
    [JsonIgnore]
    property Internal: string read FInternal write FInternal;
    [JsonIgnore(TJsonIgnoreMode.OnWrite)]
    property Password: string read FPassword write FPassword;
    [JsonIgnore(TJsonIgnoreMode.OnRead)]
    property Total: Integer read FTotal write FTotal;
  end;

  {$M+}
  /// Only the published properties come from the body.
  [JsonPublishedOnly]
  TIgnoreBodyPublished = class
  private
    FName: string;
    FWork: string;
  public
    property Work: string read FWork write FWork;
  published
    property Name: string read FName write FName;
  end;

  /// The same as TIgnoreBodyClass, as a record (hybrid binder).
  TIgnoreBodyRecord = record
    Code: string;
    [JsonIgnore]
    Internal: string;
    [JsonIgnore(TJsonIgnoreMode.OnWrite)]
    Password: string;
    [JsonIgnore(TJsonIgnoreMode.OnRead)]
    Total: Integer;
  end;

  /// <summary>
  ///   A member ignored on read is not set from the request body: a value the
  ///   server decides cannot be posted by a client.
  /// </summary>
  [TestFixture('Body binding honours [JsonIgnore] and [JsonPublishedOnly]')]
  TJsonIgnoreBindingTests = class
  public
    [Test('Class from the body: [JsonIgnore] and OnRead not set, OnWrite set')]
    procedure TestClassBody;
    [Test('Class from the body: [JsonPublishedOnly] sets only published properties')]
    procedure TestClassBodyPublishedOnly;
    [Test('Record from the body: [JsonIgnore] and OnRead not set, OnWrite set')]
    procedure TestRecordBody;
  end;

implementation

uses
  Dext.Assertions,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Web.WebApplication,
  Dext.Testing.WebApplicationFactory;

const
  Body = '{"Code":"C","Internal":"i","Password":"p","Total":7}';

var
  // What the handlers received.
  Ran: Boolean;
  GotCode, GotInternal, GotPassword, GotName, GotWork: string;
  GotTotal: Integer;

function CreateFactory: TDextApplicationFactory<TObject>;
begin
  Ran := False;
  GotCode := '';
  GotInternal := '';
  GotPassword := '';
  GotName := '';
  GotWork := '';
  GotTotal := 0;
  Result := TDextApplicationFactory<TObject>.Create
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        App.Builder.MapPost<TIgnoreBodyClass>('/ignore/class',
          procedure(B: TIgnoreBodyClass)
          begin
            Ran := True;
            GotCode := B.Code;
            GotInternal := B.Internal;
            GotPassword := B.Password;
            GotTotal := B.Total;
          end);
        App.Builder.MapPost<TIgnoreBodyPublished>('/ignore/published',
          procedure(B: TIgnoreBodyPublished)
          begin
            Ran := True;
            GotName := B.Name;
            GotWork := B.Work;
          end);
        App.Builder.MapPost<TIgnoreBodyRecord>('/ignore/record',
          procedure(B: TIgnoreBodyRecord)
          begin
            Ran := True;
            GotCode := B.Code;
            GotInternal := B.Internal;
            GotPassword := B.Password;
            GotTotal := B.Total;
          end);
      end);
end;

procedure Post(const APath, AJson: string);
var
  Factory: TDextApplicationFactory<TObject>;
  Resp: IDextTestHttpResponse;
begin
  Factory := CreateFactory;
  try
    Resp := Factory.CreateClient.PostJson(APath, AJson);
    Should(Resp.StatusCode < 300).BeTrue;
  finally
    Factory.Free;
  end;
  Should(Ran).BeTrue;
end;

{ TJsonIgnoreBindingTests }

procedure TJsonIgnoreBindingTests.TestClassBody;
begin
  Post('/ignore/class', Body);
  Should(GotCode).Be('C');
  Should(GotInternal).Be('');
  Should(GotTotal).Be(0);
  Should(GotPassword).Be('p');
end;

procedure TJsonIgnoreBindingTests.TestClassBodyPublishedOnly;
begin
  Post('/ignore/published', '{"Name":"n","Work":"w"}');
  Should(GotName).Be('n');
  Should(GotWork).Be('');
end;

procedure TJsonIgnoreBindingTests.TestRecordBody;
begin
  Post('/ignore/record', Body);
  Should(GotCode).Be('C');
  Should(GotInternal).Be('');
  Should(GotTotal).Be(0);
  Should(GotPassword).Be('p');
end;

end.
