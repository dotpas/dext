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
{  Author:  Cesar Romero & Antigravity                                      }
{  Created: 2026-01-21                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Net.RestClient;

{$I Dext.inc}

interface

uses
  System.Classes,
  System.Rtti,
  System.SyncObjs,
  System.SysUtils,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Http.Request,
  Dext.Net.Authentication,
  Dext.Net.ConnectionPool,
  Dext.Net.Engine,
  Dext.Resilience,
  Dext.Threading.Async,
  Dext.Threading.CancellationToken,
  System.ZLib;

 type
  /// <summary>Supported HTTP methods for the REST client.</summary>
  TDextHttpMethod = (hmGET, hmPOST, hmPUT, hmDELETE, hmPATCH, hmHEAD, hmOPTIONS, hmQUERY);

  /// <summary>Common MIME content types for requests and responses.</summary>
  TDextContentType = (ctJson, ctXml, ctFormUrlEncoded, ctMultipartFormData, ctBinary, ctText);

  /// <summary>Represents an HTTP request response.</summary>
  IRestResponse = interface
    ['{B1A2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D}']
    /// <summary>Returns the HTTP status code (e.g. 200, 404).</summary>
    function GetStatusCode: Integer;
    /// <summary>Returns the descriptive status text (e.g. "OK", "Not Found").</summary>
    function GetStatusText: string;
    /// <summary>Returns the response body as a Stream.</summary>
    function GetContentStream: TStream;
    /// <summary>Returns the response body as string (UTF-8).</summary>
    function GetContentString: string;
    /// <summary>Returns the raw uncompressed stream.</summary>
    function GetRawContentStream: TStream;
    /// <summary>Gets the value of a specific response header (case-insensitive lookup).</summary>
    /// <param name="AName">Header name (e.g. "Content-Type", "X-Request-Id").</param>
    /// <returns>The header value, or empty string if not found.</returns>
    function GetHeader(const AName: string): string;
    /// <summary>Returns all response headers as a TDextNetHeaders array.</summary>
    function GetHeaders: TDextNetHeaders;
    
    /// <summary>Returns true if the status code is in the 2xx range (200-299).</summary>
    function GetIsSuccess: Boolean;
    
    property StatusCode: Integer read GetStatusCode;
    property StatusText: string read GetStatusText;
    property ContentStream: TStream read GetContentStream;
    property ContentString: string read GetContentString;
    property RawContentStream: TStream read GetRawContentStream;
    /// <summary>Returns true if the status code is in the 2xx range (200-299).</summary>
    property IsSuccess: Boolean read GetIsSuccess;
  end;

  /// <summary>Represents an HTTP response whose content is automatically deserialized to type T.</summary>
  IRestResponse<T> = interface(IRestResponse)
    ['{C1D2E3F4-A5B6-4C7D-8E9F-0A1B2C3D4E5F}']
    /// <summary>Returns the deserialized object.</summary>
    function GetData: T;
    property Data: T read GetData;
  end;

  { Internal Implementation Classes - Must be in interface for Generic Visibility }

  TRestResponse = class(TInterfacedObject, IRestResponse)
  private
    FStatusCode: Integer;
    FStatusText: string;
    /// Decoded content. When the response is NOT compressed this is a read-only
    /// view over FRawContentStream's memory (same bytes, own Position) instead
    /// of a second copy of it.
    FContentStream: TStream;
    FRawContentStream: TMemoryStream;
    FHeaders: TDextNetHeaders;
  protected
    function GetStatusCode: Integer;
    function GetStatusText: string;
    function GetContentStream: TStream;
    function GetContentString: string;
    function GetRawContentStream: TStream;
    function GetHeader(const AName: string): string;
    function GetHeaders: TDextNetHeaders;
    function GetIsSuccess: Boolean;
  public
    constructor Create(AStatusCode: Integer; const AStatusText: string; AStream: TStream;
      const AHeaders: TDextNetHeaders = nil);
    /// <summary>
    ///   Response of a streamed call: the body went to the caller's stream.
    /// </summary>
    /// <param name="AErrorPayload">
    ///   nil when the call succeeded -- ContentStream stays NIL, so nobody can
    ///   accidentally materialise a 500 MB download by reading a property. On an
    ///   error status it is the bounded payload the server sent, which becomes
    ///   the readable body: it is present exactly when it is something you need
    ///   to read.
    /// </param>
    constructor CreateStreamed(AStatusCode: Integer; const AStatusText: string;
      const AHeaders: TDextNetHeaders; AErrorPayload: TStream = nil);
    destructor Destroy; override;
  end;

  TRestResponse<T> = class(TRestResponse, IRestResponse<T>)
  private
    FData: T;
  protected
    function GetData: T;
  public
    constructor Create(AStatusCode: Integer; const AStatusText: string; AStream: TStream;
      AData: T; const AHeaders: TDextNetHeaders = nil);
    destructor Destroy; override;
  end;

  // === Streaming download (S58) ===============================================

  /// <summary>
  ///   Raised once per received chunk while the response body is streaming.
  /// </summary>
  /// <param name="AContentLength">
  ///   Total announced by the server, or 0 when it did not announce one
  ///   (chunked transfer): a zero total means "unknown", not "empty".
  /// </param>
  /// <param name="AAbort">
  ///   Set it to True to stop the transfer. The call then fails with
  ///   EOperationCancelled.
  /// </param>
  /// <remarks>
  ///   Called on the WORKER thread that performs the request, not on the main
  ///   one: a VCL/FMX progress bar has to marshal (TThread.Queue/Synchronize).
  /// </remarks>
  TRestReceiveEvent = procedure(const AContentLength,
    AReadCount: Int64; var AAbort: Boolean) of object;

  /// <summary>Anonymous flavour of <see cref="TRestReceiveEvent"/>.</summary>
  TRestReceiveAnonEvent = reference to procedure(const AContentLength,
    AReadCount: Int64; var AAbort: Boolean);

  /// <summary>Options for the DownloadToFile helper.</summary>
  TRestDownloadOption = (doResume, doValidateETag, doUseContentDisposition,
    doOverwrite);
  TRestDownloadOptions = set of TRestDownloadOption;

  /// <summary>Interface for a highly configurable and asynchronous REST Client.</summary>
  IRestClient = interface
    ['{A3B4C5D6-E7F8-49A0-B1C2-D3E4F5A6B7C8}']
    /// <summary>Defines the base URL for all subsequent requests.</summary>
    function BaseUrl(const AValue: string): IRestClient;
    /// <summary>Defines the global timeout (in milliseconds).</summary>
    function Timeout(AValue: Integer): IRestClient;
    /// <summary>Configures the maximum number of automatic retries in case of network failure.</summary>
    function Retry(AValue: Integer): IRestClient;
    /// <summary>Configures whether to ignore SSL certificate validation errors (default: True).</summary>
    function IgnoreCertificateErrors(AValue: Boolean = True): IRestClient;
    /// <summary>Alias for IgnoreCertificateErrors to allow self-signed certificates.</summary>
    function AllowSelfSigned(AValue: Boolean = True): IRestClient;
    /// <summary>Configures a dynamic client certificate (PFX/P12 or PEM) from a file path.</summary>
    function ClientCertificate(const APath, APassword: string): IRestClient; overload;
    /// <summary>Configures a dynamic client certificate (PFX/P12) directly from a stream (e.g. database blob or memory).</summary>
    function ClientCertificate(ACertStream: TStream; const APassword: string): IRestClient; overload;
    /// <summary>Associates an authentication provider (Bearer, Basic, API Key).</summary>
    function Auth(AProvider: IAuthenticationProvider): IRestClient;
    /// <summary>Adds a fixed HTTP header to the client.</summary>
    function Header(const AName, AValue: string): IRestClient;
    /// <summary>Defines the default Content-Type for requests.</summary>
    function ContentType(AValue: TDextContentType): IRestClient;
    /// <summary>Attaches a custom resilience pipeline to the client.</summary>
    function ResiliencePipeline(APipeline: IResiliencePipeline): IRestClient;

    // === ContentType shortcuts ===
    /// <summary>Sets Content-Type to application/json.</summary>
    function ContentTypeJson: IRestClient;
    /// <summary>Sets Content-Type to application/xml.</summary>
    function ContentTypeXml: IRestClient;
    /// <summary>Sets Content-Type to application/x-www-form-urlencoded.</summary>
    function ContentTypeForm: IRestClient;
    /// <summary>Sets Content-Type to multipart/form-data.</summary>
    function ContentTypeMultipart: IRestClient;
    /// <summary>Sets Content-Type to application/octet-stream.</summary>
    function ContentTypeBinary: IRestClient;
    /// <summary>Sets Content-Type to text/plain.</summary>
    function ContentTypePlainText: IRestClient;

    // === POST with JSON string payload ===
    /// <summary>
    ///   Executes an asynchronous POST sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function PostJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>
    ///   Executes an asynchronous POST to AEndpoint sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function PostJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;

    // === PUT with JSON string payload ===
    /// <summary>
    ///   Executes an asynchronous PUT sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function PutJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>
    ///   Executes an asynchronous PUT to AEndpoint sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function PutJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;

    // === QUERY with JSON string payload ===
    /// <summary>
    ///   Executes an asynchronous QUERY sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function QueryJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>
    ///   Executes an asynchronous QUERY to AEndpoint sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function QueryJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;

    // === Streaming download (S58) ===
    /// <summary>
    ///   GET whose body is written straight into AResponseStream as it arrives,
    ///   instead of being buffered in memory first.
    /// </summary>
    /// <remarks>
    ///   On success the response carries headers and status but NO body:
    ///   ContentStream is nil and ContentString is empty -- the bytes went to
    ///   the caller's stream, and nobody should be able to materialise 500 MB
    ///   by touching a property. On an error status (>= 400) ContentStream
    ///   holds the (bounded) error payload instead, and the destination stream
    ///   is left exactly as it was.
    /// </remarks>
    function GetInto(const AEndpoint: string;
      const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>POST whose response body is streamed into AResponseStream.</summary>
    function PostInto(const AEndpoint: string;
      const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>PUT whose response body is streamed into AResponseStream.</summary>
    function PutInto(const AEndpoint: string;
      const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>PATCH whose response body is streamed into AResponseStream.</summary>
    function PatchInto(const AEndpoint: string;
      const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>
    ///   QUERY whose response body is streamed into AResponseStream. This is the
    ///   one that earns its keep: QUERY is how large reads with a request body
    ///   are done.
    /// </summary>
    function QueryInto(const AEndpoint: string;
      const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;

    /// <summary>
    ///   Downloads AEndpoint to a file, streaming it: memory stays flat whatever
    ///   the size.
    /// </summary>
    /// <param name="ATargetFilePath">
    ///   Where the file has to end up. Always the destination, even with
    ///   doUseContentDisposition: that option only lets the SERVER choose the
    ///   NAME, inside this file's directory, and the name is sanitised -- a
    ///   Content-Disposition filename is attacker-controlled and must never
    ///   escape that directory.
    /// </param>
    /// <param name="AOptions">
    ///   doResume: continue a previous partial download (Range, 206).
    ///   doValidateETag: ask with If-None-Match and keep the local file on 304.
    ///   doUseContentDisposition: take the name from the server.
    ///   doOverwrite: replace the destination when it already exists; without
    ///   it, an existing destination is an error BEFORE anything is downloaded.
    /// </param>
    /// <remarks>
    ///   The bytes go to "&lt;target&gt;.part" and the file only takes its final
    ///   name once the download completed, with an atomic rename. A failure
    ///   therefore never leaves a plausible-looking half file where the
    ///   application expects a whole one -- and what was received stays there,
    ///   ready for a later doResume.
    /// </remarks>
    function DownloadToFile(const AEndpoint: string; const ATargetFilePath: string;
      const AProgress: TRestReceiveAnonEvent = nil;
      const AOptions: TRestDownloadOptions = []): TAsyncBuilder<IRestResponse>;

    /// <summary>
    ///   Progress handler for every streaming call of this client. A handler set
    ///   on the request REPLACES this one for that request.
    /// </summary>
    function OnReceive(const AHandler: TRestReceiveEvent): IRestClient; overload;
    /// <summary>Anonymous flavour of OnReceive.</summary>
    function OnReceive(const AHandler: TRestReceiveAnonEvent): IRestClient; overload;
    /// <summary>The client-level handler, or nil. Used by the request builder.</summary>
    function ReceiveHandler: TRestReceiveAnonEvent;

    /// <summary>
    ///   Executes any verb streaming the response body into ATarget.
    /// </summary>
    /// <remarks>
    ///   Retries and the destination stream do not mix by accident: before every
    ///   attempt the stream is put back where it was (Size and Position), so a
    ///   second attempt overwrites the failed one instead of appending to it.
    ///   When the stream cannot seek, retries are disabled for that call --
    ///   retrying would corrupt the download, and a slow failure beats a silent
    ///   mess.
    /// </remarks>
    function ExecuteIntoAsync(AMethod: TDextHttpMethod; const AEndpoint: string;
      const ATarget: TStream; const ABody: TStream = nil; AOwnsBody: Boolean = False;
      AHeaders: IDictionary<string, string> = nil;
      const AProgress: TRestReceiveAnonEvent = nil): TAsyncBuilder<IRestResponse>;

    /// <summary>Executes an asynchronous HTTP request.</summary>
    function ExecuteAsync(AMethod: TDextHttpMethod; const AEndpoint: string; 
      const ABody: TStream = nil; AOwnsBody: Boolean = False;
      AHeaders: IDictionary<string, string> = nil): TAsyncBuilder<IRestResponse>;
  end;

  TRestClientImpl = class(TInterfacedObject, IRestClient)
  private
    FBaseUrl: string;
    FTimeout: Integer;
    FMaxRetries: Integer;
    FIgnoreCertErrors: Boolean;
    FHeaders: IDictionary<string, string>;
    FContentType: TDextContentType;
    FAuthProvider: IAuthenticationProvider;
    FPool: TConnectionPool;
    FLock: TCriticalSection;
    FResiliencePipeline: IResiliencePipeline;
    FOnReceive: TRestReceiveAnonEvent;
    FCertPath: string;
    FCertPassword: string;
    FCertStream: TMemoryStream;

    function GetFullUrl(const AEndpoint: string): string;
    /// Unico punto di esecuzione: ExecuteAsync e ExecuteIntoAsync passano di qui.
    function ExecuteCore(AMethod: TDextHttpMethod; const AEndpoint: string;
      const ABody: TStream; AOwnsBody: Boolean; AHeaders: IDictionary<string, string>;
      const ATarget: TStream; const AProgress: TRestReceiveAnonEvent;
      AOwnsTarget: Boolean = False): TAsyncBuilder<IRestResponse>;
    /// Nome di file sicuro a partire da cio' che dice il server.
    class function SanitizeFileName(const AName: string): string; static;
    /// Il filename dichiarato in Content-Disposition, gia' ripulito ('' se non c'e').
    class function DispositionFileName(const AResponse: IRestResponse): string; static;
    /// Chiude il giro: 304 lascia tutto com'e', successo rinomina, errore no.
    class procedure FinishDownload(const AResponse: IRestResponse;
      const APartPath, ATargetPath: string; AOptions: TRestDownloadOptions); static;
    /// Retorna o tamanho do arquivo de forma compativel com Delphi 10.4 Sydney+.
    class function GetFileSize(const APath: string): Int64; static;
  public
    constructor Create(const ABaseUrl: string = '');

    destructor Destroy; override;

    function BaseUrl(const AValue: string): IRestClient;
    function Timeout(AValue: Integer): IRestClient;
    function Retry(AValue: Integer): IRestClient;
    function IgnoreCertificateErrors(AValue: Boolean = True): IRestClient;
    function AllowSelfSigned(AValue: Boolean = True): IRestClient;
    function ClientCertificate(const APath, APassword: string): IRestClient; overload;
    function ClientCertificate(ACertStream: TStream; const APassword: string): IRestClient; overload;
    function Auth(AProvider: IAuthenticationProvider): IRestClient;
    function Header(const AName, AValue: string): IRestClient;
    function ContentType(AValue: TDextContentType): IRestClient;
    function ResiliencePipeline(APipeline: IResiliencePipeline): IRestClient;
    function ContentTypeJson: IRestClient;
    function ContentTypeXml: IRestClient;
    function ContentTypeForm: IRestClient;
    function ContentTypeMultipart: IRestClient;
    function ContentTypeBinary: IRestClient;
    function ContentTypePlainText: IRestClient;
    function PostJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    function PostJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;
    function PutJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    function PutJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;
    function QueryJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    function QueryJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;

    function GetInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    function PostInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    function PutInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    function PatchInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    function QueryInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    function DownloadToFile(const AEndpoint: string; const ATargetFilePath: string;
      const AProgress: TRestReceiveAnonEvent = nil;
      const AOptions: TRestDownloadOptions = []): TAsyncBuilder<IRestResponse>;
    function OnReceive(const AHandler: TRestReceiveEvent): IRestClient; overload;
    function OnReceive(const AHandler: TRestReceiveAnonEvent): IRestClient; overload;
    function ReceiveHandler: TRestReceiveAnonEvent;
    function ExecuteIntoAsync(AMethod: TDextHttpMethod; const AEndpoint: string;
      const ATarget: TStream; const ABody: TStream = nil; AOwnsBody: Boolean = False;
      AHeaders: IDictionary<string, string> = nil;
      const AProgress: TRestReceiveAnonEvent = nil): TAsyncBuilder<IRestResponse>;

    function ExecuteAsync(AMethod: TDextHttpMethod; const AEndpoint: string; 
      const ABody: TStream = nil; AOwnsBody: Boolean = False;
      AHeaders: IDictionary<string, string> = nil): TAsyncBuilder<IRestResponse>;
  end;

  /// <summary>
  ///   Fluent facade for the Dext REST Client. 
  ///   Combines high performance (Connection Pooling) with ease of use.
  /// </summary>
  TRestClient = record
  private
    FInstance: IRestClient;
    class var FSharedPool: TConnectionPool;
    class destructor Destroy;
  public
    /// <summary>Starts configuring a new REST Client.</summary>
    class function Create(const ABaseUrl: string = ''): TRestClient; static;
    
    // Configuração Fluída
    /// <summary>Sets the base URL for all subsequent requests.</summary>
    function BaseUrl(const AValue: string): TRestClient;
    /// <summary>Sets the connection/request timeout in milliseconds.</summary>
    function Timeout(AValue: Integer): TRestClient;
    /// <summary>Sets the maximum number of retry attempts for failed requests.</summary>
    function Retry(AValue: Integer): TRestClient;
    /// <summary>Configures whether to ignore SSL certificate validation errors.</summary>
    function IgnoreCertificateErrors(AValue: Boolean = True): TRestClient;
    /// <summary>Alias for IgnoreCertificateErrors to allow self-signed certificates.</summary>
    function AllowSelfSigned(AValue: Boolean = True): TRestClient;
    /// <summary>Configures a dynamic client certificate (PFX/P12 or PEM) from a file path.</summary>
    function ClientCertificate(const APath, APassword: string): TRestClient; overload;
    /// <summary>Configures a dynamic client certificate (PFX/P12) directly from a stream (e.g. database blob or memory).</summary>
    function ClientCertificate(ACertStream: TStream; const APassword: string): TRestClient; overload;
    /// <summary>Configures Bearer (JWT) authentication for requests.</summary>
    function BearerToken(const AToken: string): TRestClient;
    /// <summary>Configures basic authentication (Username/Password).</summary>
    function BasicAuth(const AUsername, APassword: string): TRestClient;
    /// <summary>Configures API Key authentication.</summary>
    function ApiKey(const AName, AValue: string; AInHeader: Boolean = True): TRestClient;
    /// <summary>
    ///   Configures OAuth 2.0 Client Credentials (M2M) authentication.
    ///   The token is automatically fetched and cached, refreshing when expired.
    /// </summary>
    /// <param name="ATokenUrl">The authorization server's token endpoint.</param>
    /// <param name="AClientId">The client identifier.</param>
    /// <param name="AClientSecret">The client secret.</param>
    /// <param name="AScope">Optional space-separated list of requested scopes.</param>
    function OAuth2ClientCredentials(const ATokenUrl, AClientId, AClientSecret: string;
      const AScope: string = ''): TRestClient;
    /// <summary>Configures a custom authentication provider.</summary>
    function Auth(AProvider: IAuthenticationProvider): TRestClient;
    /// <summary>Adds a default header that will be sent with every request from this client.</summary>
    function Header(const AName, AValue: string): TRestClient;
    /// <summary>Sets the default Content-Type for this client.</summary>
    function ContentType(AValue: TDextContentType): TRestClient;
    /// <summary>Attaches a custom resilience pipeline to the client.</summary>
    function ResiliencePipeline(APipeline: IResiliencePipeline): TRestClient;

    // === ContentType shortcuts ===
    /// <summary>Sets Content-Type to application/json.</summary>
    function ContentTypeJson: TRestClient;
    /// <summary>Sets Content-Type to application/xml.</summary>
    function ContentTypeXml: TRestClient;
    /// <summary>Sets Content-Type to application/x-www-form-urlencoded.</summary>
    function ContentTypeForm: TRestClient;
    /// <summary>Sets Content-Type to multipart/form-data.</summary>
    function ContentTypeMultipart: TRestClient;
    /// <summary>Sets Content-Type to application/octet-stream.</summary>
    function ContentTypeBinary: TRestClient;
    /// <summary>Sets Content-Type to text/plain.</summary>
    function ContentTypePlainText: TRestClient;

    // HTTP Operations
    /// <summary>Executes an asynchronous GET and returns the raw response.</summary>
    function Get(const AEndpoint: string = ''): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>Executes an asynchronous GET and automatically deserializes the JSON to type T.</summary>
    function Get<T>(const AEndpoint: string = ''): TAsyncBuilder<T>; overload;
    
    /// <summary>Executes an asynchronous POST to the base URL.</summary>
    function Post(const AEndpoint: string = ''): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>Executes an asynchronous POST with a raw stream body.</summary>
    function Post(const AEndpoint: string; const ABody: TStream): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>Executes a POST sending a payload (class or record) serialized as JSON and awaits a typed response.</summary>
    function Post<TRes>(const AEndpoint: string; const ABody: TRes): TAsyncBuilder<IRestResponse<TRes>>; overload;
    /// <summary>
    ///   Executes an asynchronous POST sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function PostJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>
    ///   Executes an asynchronous POST to AEndpoint sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function PostJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;

    /// <summary>Executes an asynchronous PUT to the base URL.</summary>
    function Put(const AEndpoint: string = ''): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>Executes an asynchronous PUT with a raw stream body.</summary>
    function Put(const AEndpoint: string; const ABody: TStream): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>Executes a PUT sending a payload (class or record) serialized as JSON and awaits a typed response.</summary>
    function Put<TRes>(const AEndpoint: string; const ABody: TRes): TAsyncBuilder<IRestResponse<TRes>>; overload;
    /// <summary>Executes an asynchronous PUT and automatically deserializes the JSON response to type T.</summary>
    function Put<T>(const AEndpoint: string = ''): TAsyncBuilder<T>; overload;
    /// <summary>
    ///   Executes an asynchronous PUT sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function PutJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>
    ///   Executes an asynchronous PUT to AEndpoint sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function PutJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;

    /// <summary>Executes an asynchronous DELETE request.</summary>
    function Delete(const AEndpoint: string = ''): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>Executes an asynchronous DELETE and automatically deserializes the JSON response to type T.</summary>
    function Delete<T>(const AEndpoint: string = ''): TAsyncBuilder<T>; overload;

    /// <summary>Executes an asynchronous QUERY to the base URL.</summary>
    function Query(const AEndpoint: string = ''): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>Executes an asynchronous QUERY with a raw stream body.</summary>
    function Query(const AEndpoint: string; const ABody: TStream): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>Executes a QUERY sending a payload (class or record) serialized as JSON and awaits a typed response.</summary>
    function Query<TRes>(const AEndpoint: string; const ABody: TRes): TAsyncBuilder<IRestResponse<TRes>>; overload;
    /// <summary>Executes an asynchronous QUERY and automatically deserializes the JSON response to type T.</summary>
    function Query<T>(const AEndpoint: string = ''): TAsyncBuilder<T>; overload;
    /// <summary>
    ///   Executes an asynchronous QUERY sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function QueryJson(const APayload: string): TAsyncBuilder<IRestResponse>; overload;
    /// <summary>
    ///   Executes an asynchronous QUERY to AEndpoint sending a raw JSON string.
    ///   Encapsulates stream creation and UTF-8 encoding internally.
    /// </summary>
    function QueryJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>; overload;
    
    function ExecuteAsync(AMethod: TDextHttpMethod; const AEndpoint: string; 
      const ABody: TStream = nil; AOwnsBody: Boolean = False;
      AHeaders: IDictionary<string, string> = nil): TAsyncBuilder<IRestResponse>;

    // === Streaming download (S58) ===
    /// <summary>GET streamed straight into AResponseStream (no memory buffering).</summary>
    function GetInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>POST whose response is streamed into AResponseStream.</summary>
    function PostInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>PUT whose response is streamed into AResponseStream.</summary>
    function PutInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>PATCH whose response is streamed into AResponseStream.</summary>
    function PatchInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>QUERY whose response is streamed into AResponseStream.</summary>
    function QueryInto(const AEndpoint: string; const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
    /// <summary>Downloads to a file, streaming (memory flat) with atomic rename.</summary>
    function DownloadToFile(const AEndpoint: string; const ATargetFilePath: string;
      const AProgress: TRestReceiveAnonEvent = nil;
      const AOptions: TRestDownloadOptions = []): TAsyncBuilder<IRestResponse>;
    /// <summary>Progress handler for every streaming call of this client.</summary>
    function OnReceive(const AHandler: TRestReceiveEvent): TRestClient; overload;
    /// <summary>Anonymous flavour of OnReceive.</summary>
    function OnReceive(const AHandler: TRestReceiveAnonEvent): TRestClient; overload;

    /// <summary>
    ///   Executes a request defined by a THttpRequestInfo object (compatible with .http parsers).
    /// </summary>
    function Execute(RequestInfo: THttpRequestInfo): TAsyncBuilder<IRestResponse>;

    property Instance: IRestClient read FInstance;
  end;

  /// <summary>
  ///   Exception for REST Client errors.
  /// </summary>
  EDextRestException = class(Exception);

function RestClient(const ABaseUrl: string = ''): TRestClient;

implementation

uses
  System.Math,
  System.IOUtils, // DownloadToFile: file temporaneo + rename atomico
  System.NetEncoding, // filename*=UTF-8'' (RFC 5987)
  Dext.Json,
  Dext.Logging.Tracing;

function RestClient(const ABaseUrl: string = ''): TRestClient;
begin
  Result := TRestClient.Create(ABaseUrl);
end;

type
  /// <summary>
  ///   Read-only view over memory owned by another stream: same bytes, no copy,
  ///   but an independent Position so callers can read both views concurrently.
  /// </summary>
  /// <remarks>
  ///   Used when the response is not compressed and the decoded content is
  ///   byte-for-byte the raw content: duplicating it would double the memory of
  ///   every response for no benefit. The view never outlives the stream that
  ///   owns the memory (both are fields of the same TRestResponse).
  /// </remarks>
  TDextMemoryView = class(TCustomMemoryStream)
  public
    constructor Create(AMemory: Pointer; ASize: NativeInt);
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

constructor TDextMemoryView.Create(AMemory: Pointer; ASize: NativeInt);
begin
  inherited Create;
  SetPointer(AMemory, ASize);
end;

function TDextMemoryView.Write(const Buffer; Count: Longint): Longint;
begin
  raise EStreamError.Create('Response content stream is read-only.');
end;

{ TRestResponse }

constructor TRestResponse.Create(AStatusCode: Integer; const AStatusText: string; AStream: TStream;
  const AHeaders: TDextNetHeaders);
var
  ContentEncoding: string;
  Decompressor: TZDecompressionStream;
begin
  inherited Create;
  FStatusCode := AStatusCode;
  FStatusText := AStatusText;
  FHeaders := AHeaders;
  FRawContentStream := TMemoryStream.Create;
  if not Assigned(AStream) then
  begin
    // No payload: keep an empty decoded stream, as before.
    FContentStream := TMemoryStream.Create;
    Exit;
  end;

  AStream.Position := 0;
  FRawContentStream.CopyFrom(AStream, AStream.Size);
  FRawContentStream.Position := 0;

  ContentEncoding := GetHeader('Content-Encoding');
  if SameText(ContentEncoding, 'gzip') or SameText(ContentEncoding, 'deflate')
  then
  begin
    // Compressed: the decoded content really is different from the raw bytes,
    // so it needs its own stream.
    FContentStream := TMemoryStream.Create;
    if SameText(ContentEncoding, 'gzip') then
      Decompressor := TZDecompressionStream.Create(FRawContentStream, 31)
    else
      Decompressor := TZDecompressionStream.Create(FRawContentStream, 15);
    try
      TMemoryStream(FContentStream).CopyFrom(Decompressor, 0);
    finally
      Decompressor.Free;
    end;
  end
  else
  begin
    // Not compressed: decoded content == raw content, byte for byte. Copying it
    // doubled the memory of every response for nothing -- a 500 MB download kept
    // 1 GB alive. A view shares the bytes and keeps its own Position, so
    // ContentStream and RawContentStream stay independent for the caller.
    FContentStream := TDextMemoryView.Create(FRawContentStream.Memory,
      FRawContentStream.Size);
  end;

  FContentStream.Position := 0;
  FRawContentStream.Position := 0;
end;

constructor TRestResponse.CreateStreamed(AStatusCode: Integer;
  const AStatusText: string; const AHeaders: TDextNetHeaders; AErrorPayload: TStream);
begin
  if AErrorPayload <> nil then
  begin
    // C'e' un corpo da leggere (e' un errore): stessa strada di sempre.
    Create(AStatusCode, AStatusText, AErrorPayload, AHeaders);
    Exit;
  end;
  inherited Create;
  FStatusCode := AStatusCode;
  FStatusText := AStatusText;
  FHeaders := AHeaders;
  FContentStream := nil;
  FRawContentStream := nil;
end;

destructor TRestResponse.Destroy;
begin
  // The view must go first: it points into FRawContentStream's memory.
  FContentStream.Free;
  FRawContentStream.Free;
  inherited;
end;

function TRestResponse.GetContentStream: TStream;
begin
  Result := FContentStream;
end;

function TRestResponse.GetRawContentStream: TStream;
begin
  Result := FRawContentStream;
end;

function TRestResponse.GetContentString: string;
var
  Data: TBytes;
begin
  // Nil dopo una chiamata in streaming andata bene: il corpo e' nello stream del
  // chiamante, e da qui non deve rimaterializzarsi.
  if (FContentStream = nil) or (FContentStream.Size = 0) then Exit('');

  FContentStream.Position := 0;
  SetLength(Data, FContentStream.Size);
  FContentStream.ReadBuffer(Data[0], FContentStream.Size);
  Result := TEncoding.UTF8.GetString(Data);
end;

function TRestResponse.GetHeader(const AName: string): string;
var
  i: Integer;
begin
  for i := 0 to High(FHeaders) do
    if SameText(FHeaders[i].Name, AName) then
      Exit(FHeaders[i].Value);
  Result := '';
end;

function TRestResponse.GetHeaders: TDextNetHeaders;
begin
  Result := FHeaders;
end;

function TRestResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

function TRestResponse.GetStatusText: string;
begin
  Result := FStatusText;
end;

function TRestResponse.GetIsSuccess: Boolean;
begin
  Result := (FStatusCode >= 200) and (FStatusCode < 300);
end;

{ TRestResponse<T> }

constructor TRestResponse<T>.Create(AStatusCode: Integer; const AStatusText: string; AStream: TStream;
  AData: T; const AHeaders: TDextNetHeaders);
begin
  inherited Create(AStatusCode, AStatusText, AStream, AHeaders);
  FData := AData;
end;

destructor TRestResponse<T>.Destroy;
begin
  if TValue.From<T>(FData).IsObject then
    TValue.From<T>(FData).AsObject.Free;
  inherited;
end;

function TRestResponse<T>.GetData: T;
begin
  Result := FData;
end;

{ TRestClientImpl }

constructor TRestClientImpl.Create(const ABaseUrl: string);
begin
  inherited Create;
  FBaseUrl := ABaseUrl;
  FTimeout := 30000;
  FHeaders := TCollections.CreateDictionary<string, string>;
  FContentType := ctJson;
  FIgnoreCertErrors := True;
  FPool := TConnectionPool(TRestClient.FSharedPool);
  FLock := TCriticalSection.Create;
end;

destructor TRestClientImpl.Destroy;
begin
  // FHeaders is ARC
  FCertStream.Free;
  FLock.Free;
  inherited;
end;

function TRestClientImpl.IgnoreCertificateErrors(AValue: Boolean): IRestClient;
begin
  FIgnoreCertErrors := AValue;
  Result := Self;
end;

function TRestClientImpl.AllowSelfSigned(AValue: Boolean): IRestClient;
begin
  Result := IgnoreCertificateErrors(AValue);
end;

function TRestClientImpl.ClientCertificate(const APath, APassword: string): IRestClient;
begin
  FLock.Enter;
  try
    FCertPath := APath;
    FCertPassword := APassword;
    FreeAndNil(FCertStream);
  finally
    FLock.Leave;
  end;
  Result := Self;
end;

function TRestClientImpl.ClientCertificate(ACertStream: TStream; const APassword: string): IRestClient;
begin
  FLock.Enter;
  try
    FCertPath := '';
    FCertPassword := APassword;
    FreeAndNil(FCertStream);
    if Assigned(ACertStream) then
    begin
      FCertStream := TMemoryStream.Create;
      ACertStream.Position := 0;
      FCertStream.CopyFrom(ACertStream, ACertStream.Size);
      FCertStream.Position := 0;
    end;
  finally
    FLock.Leave;
  end;
  Result := Self;
end;

function TRestClientImpl.GetFullUrl(const AEndpoint: string): string;
begin
  if FBaseUrl = '' then Exit(AEndpoint);
  
  Result := FBaseUrl;
  if (AEndpoint <> '') then
  begin
    if not Result.EndsWith('/') and not AEndpoint.StartsWith('/') then
      Result := Result + '/';
    Result := Result + AEndpoint;
  end;
end;

function TRestClientImpl.BaseUrl(const AValue: string): IRestClient;
begin
  FBaseUrl := AValue;
  Result := Self;
end;

function TRestClientImpl.Auth(AProvider: IAuthenticationProvider): IRestClient;
begin
  FAuthProvider := AProvider;
  Result := Self;
end;

function TRestClientImpl.ContentType(AValue: TDextContentType): IRestClient;
begin
  FContentType := AValue;
  Result := Self;
end;

function TRestClientImpl.ResiliencePipeline(APipeline: IResiliencePipeline): IRestClient;
begin
  FResiliencePipeline := APipeline;
  Result := Self;
end;

function TRestClientImpl.ContentTypeJson: IRestClient;
begin
  Result := ContentType(ctJson);
end;

function TRestClientImpl.ContentTypeXml: IRestClient;
begin
  Result := ContentType(ctXml);
end;

function TRestClientImpl.ContentTypeForm: IRestClient;
begin
  Result := ContentType(ctFormUrlEncoded);
end;

function TRestClientImpl.ContentTypeMultipart: IRestClient;
begin
  Result := ContentType(ctMultipartFormData);
end;

function TRestClientImpl.ContentTypeBinary: IRestClient;
begin
  Result := ContentType(ctBinary);
end;

function TRestClientImpl.ContentTypePlainText: IRestClient;
begin
  Result := ContentType(ctText);
end;

function TRestClientImpl.PostJson(const APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := PostJson('', APayload);
end;

function TRestClientImpl.PostJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>;
begin
  ContentTypeJson; // Set Content-Type automatically
  Result := ExecuteAsync(hmPOST, AEndpoint,
    TStringStream.Create(APayload, TEncoding.UTF8), True);
end;

function TRestClientImpl.PutJson(const APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := PutJson('', APayload);
end;

function TRestClientImpl.PutJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>;
begin
  ContentTypeJson; // Set Content-Type automatically
  Result := ExecuteAsync(hmPUT, AEndpoint,
    TStringStream.Create(APayload, TEncoding.UTF8), True);
end;

function TRestClientImpl.QueryJson(const APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := QueryJson('', APayload);
end;

function TRestClientImpl.QueryJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>;
begin
  ContentTypeJson; // Set Content-Type automatically
  Result := ExecuteAsync(hmQUERY, AEndpoint,
    TStringStream.Create(APayload, TEncoding.UTF8), True);
end;

function TRestClientImpl.Header(const AName, AValue: string): IRestClient;
begin
  FLock.Enter;
  try
    FHeaders.AddOrSetValue(AName, AValue);
  finally
    FLock.Leave;
  end;
  Result := Self;
end;

function TRestClientImpl.Retry(AValue: Integer): IRestClient;
begin
  FMaxRetries := AValue;
  Result := Self;
end;

function TRestClientImpl.Timeout(AValue: Integer): IRestClient;
begin
  FTimeout := AValue;
  Result := Self;
end;

function TRestClientImpl.ExecuteAsync(AMethod: TDextHttpMethod; const AEndpoint: string; 
  const ABody: TStream; AOwnsBody: Boolean; AHeaders: IDictionary<string, string>): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteCore(AMethod, AEndpoint, ABody, AOwnsBody, AHeaders, nil, nil);
end;

function TRestClientImpl.ExecuteIntoAsync(AMethod: TDextHttpMethod; const AEndpoint: string;
  const ATarget: TStream; const ABody: TStream; AOwnsBody: Boolean;
  AHeaders: IDictionary<string, string>;
  const AProgress: TRestReceiveAnonEvent): TAsyncBuilder<IRestResponse>;
var
  Handler: TRestReceiveAnonEvent;
begin
  if ATarget = nil then
    raise EArgumentNilException.Create('ExecuteIntoAsync: target stream is required');
  // Quello della richiesta SOSTITUISCE quello del client (non si sommano).
  Handler := AProgress;
  if not Assigned(Handler) then
    Handler := FOnReceive;
  Result := ExecuteCore(AMethod, AEndpoint, ABody, AOwnsBody, AHeaders, ATarget, Handler);
end;

function TRestClientImpl.ExecuteCore(AMethod: TDextHttpMethod; const AEndpoint: string;
  const ABody: TStream; AOwnsBody: Boolean; AHeaders: IDictionary<string, string>;
  const ATarget: TStream; const AProgress: TRestReceiveAnonEvent;
  AOwnsTarget: Boolean): TAsyncBuilder<IRestResponse>;
var
  Streaming: Boolean;
  CanSeek: Boolean;
  TargetBase, TargetSize: Int64;
  Auth: IAuthenticationProvider;
  ContentTypeStr: string;
  HasAcceptEncoding: Boolean;
  HasContentType: Boolean;
  Headers: TDextNetHeaders;
  HeadList: TList<TDextNetHeader>;
  i: Integer;
  Pair: TPair<string, string>;
  Retries: Integer;
  Timeout: Integer;
  Url: string;
  CertPath: string;
  CertPassword: string;
  CertStream: TMemoryStream;
begin
  Url := GetFullUrl(AEndpoint);
  Retries := FMaxRetries;

  Streaming := ATarget <> nil;
  CanSeek := False;
  TargetBase := 0;
  TargetSize := 0;
  if Streaming then
  begin
    // Dove sta il chiamante ADESSO: e' il punto a cui rimettere lo stream prima
    // di ogni tentativo, cosi' un retry riscrive il tentativo fallito invece di
    // accodarcisi. Se lo stream non sa muoversi, il retry lo si TOGLIE: ritentare
    // corromperebbe il download, e fallire piano e' meglio di un file sbagliato.
    try
      TargetBase := ATarget.Position;
      TargetSize := ATarget.Size;
      CanSeek := True;
    except
      on E: Exception do
        CanSeek := False;
    end;
    if not CanSeek then
      Retries := 0;
  end;
  Timeout := FTimeout;
  Auth := FAuthProvider;
  CertStream := nil;
  
  // Snapshot headers and certificate (Thread Safety)
  HeadList := TList<TDextNetHeader>.Create;
  try
    FLock.Enter;
    try
      CertPath := FCertPath;
      CertPassword := FCertPassword;
      if Assigned(FCertStream) then
      begin
        CertStream := TMemoryStream.Create;
        FCertStream.Position := 0;
        CertStream.CopyFrom(FCertStream, FCertStream.Size);
        CertStream.Position := 0;
      end;
      for Pair in FHeaders do
        HeadList.Add(TDextNetHeader.Create(Pair.Key, Pair.Value));
    finally
      FLock.Leave;
    end;
      
    if Assigned(Auth) then
    begin
       if Auth is TApiKeyAuthProvider then
         HeadList.Add(TDextNetHeader.Create(TApiKeyAuthProvider(Auth).Key, Auth.GetHeaderValue))
       else
         HeadList.Add(TDextNetHeader.Create('Authorization', Auth.GetHeaderValue));
    end;
 
    if Assigned(AHeaders) then
    begin
      for Pair in AHeaders do
        HeadList.Add(TDextNetHeader.Create(Pair.Key, Pair.Value));
    end;

    HasAcceptEncoding := False;
    for i := 0 to HeadList.Count - 1 do
    begin
      if SameText(HeadList[i].Name, 'Accept-Encoding') then
      begin
        HasAcceptEncoding := True;
        Break;
      end;
    end;

    // In streaming la codifica la negozia l'ENGINE: sull'RTL accende la
    // decompressione al volo (e chiede lui gzip), su Indy chiede identity perche'
    // li' la decompressione passa da un buffer temporaneo e vanificherebbe lo
    // streaming. Imporre qui "gzip, deflate" scavalcherebbe quella scelta.
    if (not HasAcceptEncoding) and (not Streaming) then
      HeadList.Add(TDextNetHeader.Create('Accept-Encoding', 'gzip, deflate'));

    HasContentType := False;
    for i := 0 to HeadList.Count - 1 do
    begin
      if SameText(HeadList[i].Name, 'Content-Type') then
      begin
        HasContentType := True;
        Break;
      end;
    end;

    if not HasContentType and Assigned(ABody) then
    begin
      case FContentType of
        ctJson: ContentTypeStr := 'application/json';
        ctXml: ContentTypeStr := 'application/xml';
        ctFormUrlEncoded: ContentTypeStr := 'application/x-www-form-urlencoded';
        ctMultipartFormData: ContentTypeStr := 'multipart/form-data';
        ctBinary: ContentTypeStr := 'application/octet-stream';
        ctText: ContentTypeStr := 'text/plain';
        else ContentTypeStr := '';
      end;
      if ContentTypeStr <> '' then
        HeadList.Add(TDextNetHeader.Create('Content-Type', ContentTypeStr));
    end;
    
    Headers := HeadList.ToArray;
  finally
    HeadList.Free;
  end;
  
  Result := TAsyncTask.Run<IRestResponse>(
    TFunc<IRestResponse>(
      function: IRestResponse
      var
        MethodStr: string;
        LSpan: TSpan;
        LPipeline: IResiliencePipeline;
      begin
        case AMethod of
          hmGET:    MethodStr := 'GET';
          hmPOST:   MethodStr := 'POST';
          hmPUT:    MethodStr := 'PUT';
          hmDELETE: MethodStr := 'DELETE';
          hmPATCH:  MethodStr := 'PATCH';
          hmHEAD:   MethodStr := 'HEAD';
          hmOPTIONS:MethodStr := 'OPTIONS';
          hmQUERY:  MethodStr := 'QUERY';
          else MethodStr := 'GET';
        end;

        LSpan := TTracer.BeginSpan('HTTP Outbound', 'HTTP');
        LSpan.SetAttribute('http.url', Url);
        LSpan.SetAttribute('http.method', MethodStr);

        try
          try
            LPipeline := FResiliencePipeline;
            if not Assigned(LPipeline) then
            begin
              LPipeline := TResiliencePipelineImpl.Create;
              if Retries > 0 then
                LPipeline.AddRetry(Retries, 100);
            end;

            Result := LPipeline.Execute(
              TFunc<TValue>(
                function: TValue
                var
                  HttpClient: IDextHttpEngine;
                  Response: IDextHttpResponse;
                begin
                  HttpClient := TConnectionPool(TRestClient.FSharedPool).Acquire;
                  try
                    HttpClient.SetConnectionTimeout(Timeout);
                    HttpClient.SetIgnoreCertificateErrors(FIgnoreCertErrors);
                    HttpClient.SetSendTimeout(Timeout);
                    HttpClient.SetResponseTimeout(Timeout);

                    if Assigned(CertStream) then
                    begin
                      CertStream.Position := 0;
                      HttpClient.SetClientCertificate(CertStream, CertPassword);
                    end
                    else if CertPath <> '' then
                      HttpClient.SetClientCertificate(CertPath, CertPassword)
                    else
                      HttpClient.ClearClientCertificate;

                    if Streaming then
                    begin
                      // Ogni tentativo riparte da dove stava il chiamante.
                      if CanSeek then
                      begin
                        ATarget.Size := TargetSize;
                        ATarget.Position := TargetBase;
                      end;
                      Response := HttpClient.ExecuteInto(MethodStr, Url, ABody, Headers,
                        ATarget,
                        procedure(const AContentLength, AReadCount: Int64; var AAbort: Boolean)
                        begin
                          if Assigned(AProgress) then
                            AProgress(AContentLength, AReadCount, AAbort);
                        end);
                      // Corpo assente se e' andata bene, payload d'errore se no.
                      Result := TValue.From<IRestResponse>(TRestResponse.CreateStreamed(
                        Response.GetStatusCode, Response.GetStatusText,
                        Response.GetHeaders, Response.GetContentStream));
                    end
                    else
                    begin
                      Response := HttpClient.Execute(MethodStr, Url, ABody, Headers);
                      Result := TValue.From<IRestResponse>(TRestResponse.Create(Response.GetStatusCode, Response.GetStatusText, Response.GetContentStream, Response.GetHeaders));
                    end;
                    
                    LSpan.SetAttribute('http.status_code', Response.GetStatusCode);
                    LSpan.SetStatus('Success');
                  finally
                    HttpClient.ClearClientCertificate;
                    TConnectionPool(TRestClient.FSharedPool).Release(HttpClient);
                  end;
                end
              )
            ).AsType<IRestResponse>;
          except
            on E: Exception do
            begin
              LSpan.SetStatus('Error', E.Message);
              raise;
            end;
          end;
        finally
          LSpan.Finish;
          CertStream.Free;
          if AOwnsBody and Assigned(ABody) then
            ABody.Free;
          // Il file .part si chiude QUI, dentro il task: chi viene dopo (il
          // rename) deve trovarlo gia' rilasciato.
          if AOwnsTarget and Assigned(ATarget) then
            ATarget.Free;
        end;
      end
    )
  );
end;

// === Streaming download (S58) ================================================

function TRestClientImpl.GetInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteIntoAsync(hmGET, AEndpoint, AResponseStream);
end;

function TRestClientImpl.PostInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteIntoAsync(hmPOST, AEndpoint, AResponseStream);
end;

function TRestClientImpl.PutInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteIntoAsync(hmPUT, AEndpoint, AResponseStream);
end;

function TRestClientImpl.PatchInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteIntoAsync(hmPATCH, AEndpoint, AResponseStream);
end;

function TRestClientImpl.QueryInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteIntoAsync(hmQUERY, AEndpoint, AResponseStream);
end;

class function TRestClientImpl.SanitizeFileName(const AName: string): string;
var
  C: Char;
begin
  // Del nome dato dal server si tiene SOLO l'ultimo segmento, e nemmeno quello
  // per intero: separatori, '..' e caratteri non validi via. Cosi' un
  // Content-Disposition ostile non puo' uscire dalla cartella di destinazione.
  Result := AName.Trim(['"', ' ']);
  Result := Result.Replace('\', '/');
  if Result.Contains('/') then
    Result := Result.Substring(Result.LastIndexOf('/') + 1);
  Result := Result.Replace('..', '');
  for C in TPath.GetInvalidFileNameChars do
    Result := Result.Replace(C, '');
  Result := Result.Trim(['.', ' ']);
end;

class function TRestClientImpl.DispositionFileName(const AResponse: IRestResponse): string;
var
  Header, Part: string;
  Pieces: TArray<string>;
begin
  Result := '';
  Header := AResponse.GetHeader('Content-Disposition');
  if Header = '' then
    Exit;
  Pieces := Header.Split([';']);
  // filename*=UTF-8''nome vince su filename="nome" (RFC 5987).
  for Part in Pieces do
    if Part.Trim.StartsWith('filename*=', True) then
    begin
      Result := Part.Trim.Substring(Length('filename*='));
      if Result.Contains('''''') then
        Result := Result.Substring(Result.LastIndexOf('''''') + 2);
      Result := TNetEncoding.URL.Decode(Result);
      Break;
    end;
  if Result = '' then
    for Part in Pieces do
      if Part.Trim.StartsWith('filename=', True) then
      begin
        Result := Part.Trim.Substring(Length('filename='));
        Break;
      end;
  Result := SanitizeFileName(Result);
end;

class function TRestClientImpl.GetFileSize(const APath: string): Int64;
{$IF CompilerVersion >= 35.0}
begin
  Result := TFile.GetSize(APath);
end;
{$ELSE}
var
  Stream: TFileStream;
begin
  if not TFile.Exists(APath) then
    Exit(0);
  try
    Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      Result := Stream.Size;
    finally
      Stream.Free;
    end;
  except
    Result := 0;
  end;
end;
{$IFEND}

class procedure TRestClientImpl.FinishDownload(const AResponse: IRestResponse;
  const APartPath, ATargetPath: string; AOptions: TRestDownloadOptions);
var
  FinalPath, Name: string;
begin
  // 304: il file locale e' ancora buono. Non si tocca niente, e il .part vuoto
  // che era stato aperto se ne va.
  if AResponse.GetStatusCode = 304 then
  begin
    if TFile.Exists(APartPath) and (GetFileSize(APartPath) = 0) then
      TFile.Delete(APartPath);
    Exit;
  end;

  // Errore: il gate non ha scritto niente nel .part, quindi quello che c'era
  // resta li' -- pronto per un doResume piu' avanti. Nessun rename.
  if not AResponse.GetIsSuccess then
    Exit;

  FinalPath := ATargetPath;
  if doUseContentDisposition in AOptions then
  begin
    Name := DispositionFileName(AResponse);
    if Name <> '' then
      // Il nome lo sceglie il server, la CARTELLA no.
      FinalPath := TPath.Combine(TPath.GetDirectoryName(ATargetPath), Name);
  end;

  if TFile.Exists(FinalPath) then
  begin
    if not (doOverwrite in AOptions) then
      raise EInOutError.CreateFmt(
        'DownloadToFile: "%s" esiste gia. Passa doOverwrite per sostituirlo.',
        [FinalPath]);
    TFile.Delete(FinalPath);
  end;
  // Il file prende il nome definitivo solo ORA: o e' intero, o non c'e'.
  TFile.Move(APartPath, FinalPath);
end;

function TRestClientImpl.DownloadToFile(const AEndpoint: string;
  const ATargetFilePath: string; const AProgress: TRestReceiveAnonEvent;
  const AOptions: TRestDownloadOptions): TAsyncBuilder<IRestResponse>;
var
  PartPath, TargetPath, ETagPath: string;
  Part: TFileStream;
  Headers: IDictionary<string, string>;
  Handler: TRestReceiveAnonEvent;
  Existing: Int64;
  Opts: TRestDownloadOptions;
  NextProc: TProc<IRestResponse>;
begin
  TargetPath := TPath.GetFullPath(ATargetFilePath);
  Opts := AOptions;

  // Se la destinazione c'e' gia' e non si puo' sostituire, meglio saperlo PRIMA
  // di scaricare mezzo giga.
  if TFile.Exists(TargetPath) and not (doOverwrite in Opts) and
     not (doValidateETag in Opts) and not (doUseContentDisposition in Opts) then
    raise EInOutError.CreateFmt(
      'DownloadToFile: "%s" esiste gia. Passa doOverwrite per sostituirlo.',
      [TargetPath]);

  ForceDirectories(TPath.GetDirectoryName(TargetPath));
  PartPath := TargetPath + '.part';
  ETagPath := TargetPath + '.etag';

  Headers := TCollections.CreateDictionary<string, string>;
  Existing := 0;
  if (doResume in Opts) and TFile.Exists(PartPath) then
  begin
    Existing := GetFileSize(PartPath);
    if Existing > 0 then
      // "Dammi il resto": se il server sta al gioco risponde 206 e si accoda.
      Headers.AddOrSetValue('Range', Format('bytes=%d-', [Existing]));
  end;
  if (doValidateETag in Opts) and TFile.Exists(ETagPath) and TFile.Exists(TargetPath) then
    Headers.AddOrSetValue('If-None-Match', TFile.ReadAllText(ETagPath).Trim);

  if Existing > 0 then
  begin
    Part := TFileStream.Create(PartPath, fmOpenReadWrite or fmShareDenyWrite);
    Part.Seek(0, soEnd); // il gia' scaricato non si tocca
  end
  else
    Part := TFileStream.Create(PartPath, fmCreate or fmShareDenyWrite);

  Handler := AProgress;
  if not Assigned(Handler) then
    Handler := FOnReceive;

  NextProc :=
    procedure(AResponse: IRestResponse)
    var
      ETag: string;
    begin
      FinishDownload(AResponse, PartPath, TargetPath, Opts);
      if AResponse.GetIsSuccess then
      begin
        ETag := AResponse.GetHeader('ETag');
        if ETag <> '' then
          TFile.WriteAllText(ETagPath, ETag);
      end;
    end;

  // ExecuteCore possiede il .part e lo chiude dentro il task; il rename avviene
  // dopo, a file gia' rilasciato.
  Result := ExecuteCore(hmGET, AEndpoint, nil, False, Headers, Part, Handler, True)
    .ThenBy(NextProc);
end;

function TRestClientImpl.OnReceive(const AHandler: TRestReceiveEvent): IRestClient;
begin
  if Assigned(AHandler) then
    FOnReceive :=
      procedure(const AContentLength, AReadCount: Int64; var AAbort: Boolean)
      begin
        AHandler(AContentLength, AReadCount, AAbort);
      end
  else
    FOnReceive := nil;
  Result := Self;
end;

function TRestClientImpl.OnReceive(const AHandler: TRestReceiveAnonEvent): IRestClient;
begin
  FOnReceive := AHandler;
  Result := Self;
end;

function TRestClientImpl.ReceiveHandler: TRestReceiveAnonEvent;
begin
  Result := FOnReceive;
end;

{ TRestClient }

class destructor TRestClient.Destroy;
begin
  FSharedPool.Free;
end;

class function TRestClient.Create(const ABaseUrl: string): TRestClient;
var
  NewPool: TConnectionPool;
begin
  // Thread-safe pool initialization
  if not Assigned(FSharedPool) then
  begin
    NewPool := TConnectionPool.Create;
    if TInterlocked.CompareExchange(Pointer(FSharedPool), Pointer(NewPool), nil) <> nil then
      NewPool.Free;
  end;
  Result.FInstance := TRestClientImpl.Create(ABaseUrl);
end;

function TRestClient.BaseUrl(const AValue: string): TRestClient;
begin
  FInstance.BaseUrl(AValue);
  Result := Self;
end;

function TRestClient.IgnoreCertificateErrors(AValue: Boolean): TRestClient;
begin
  FInstance.IgnoreCertificateErrors(AValue);
  Result := Self;
end;

function TRestClient.AllowSelfSigned(AValue: Boolean): TRestClient;
begin
  FInstance.AllowSelfSigned(AValue);
  Result := Self;
end;

function TRestClient.ClientCertificate(const APath, APassword: string): TRestClient;
begin
  FInstance.ClientCertificate(APath, APassword);
  Result := Self;
end;

function TRestClient.ClientCertificate(ACertStream: TStream; const APassword: string): TRestClient;
begin
  FInstance.ClientCertificate(ACertStream, APassword);
  Result := Self;
end;

function TRestClient.BearerToken(const AToken: string): TRestClient;
begin
  FInstance.Auth(TBearerAuthProvider.Create(AToken));
  Result := Self;
end;

function TRestClient.BasicAuth(const AUsername, APassword: string): TRestClient;
begin
  FInstance.Auth(TBasicAuthProvider.Create(AUsername, APassword));
  Result := Self;
end;

function TRestClient.ApiKey(const AName, AValue: string; AInHeader: Boolean): TRestClient;
begin
  if AInHeader then
    FInstance.Auth(TApiKeyAuthProvider.Create(AName, AValue));
  Result := Self;
end;

function TRestClient.OAuth2ClientCredentials(const ATokenUrl, AClientId, AClientSecret: string;
  const AScope: string): TRestClient;
begin
  FInstance.Auth(TOAuth2ClientCredentialsProvider.Create(ATokenUrl, AClientId, AClientSecret, AScope));
  Result := Self;
end;

function TRestClient.Auth(AProvider: IAuthenticationProvider): TRestClient;
begin
  FInstance.Auth(AProvider);
  Result := Self;
end;

function TRestClient.ContentType(AValue: TDextContentType): TRestClient;
begin
  FInstance.ContentType(AValue);
  Result := Self;
end;

function TRestClient.ResiliencePipeline(APipeline: IResiliencePipeline): TRestClient;
begin
  FInstance.ResiliencePipeline(APipeline);
  Result := Self;
end;

function TRestClient.ContentTypeJson: TRestClient;
begin
  FInstance.ContentTypeJson;
  Result := Self;
end;

function TRestClient.ContentTypeXml: TRestClient;
begin
  FInstance.ContentTypeXml;
  Result := Self;
end;

function TRestClient.ContentTypeForm: TRestClient;
begin
  FInstance.ContentTypeForm;
  Result := Self;
end;

function TRestClient.ContentTypeMultipart: TRestClient;
begin
  FInstance.ContentTypeMultipart;
  Result := Self;
end;

function TRestClient.ContentTypeBinary: TRestClient;
begin
  FInstance.ContentTypeBinary;
  Result := Self;
end;

function TRestClient.ContentTypePlainText: TRestClient;
begin
  FInstance.ContentTypePlainText;
  Result := Self;
end;

function TRestClient.PostJson(const APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.PostJson(APayload);
end;

function TRestClient.PostJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.PostJson(AEndpoint, APayload);
end;

function TRestClient.PutJson(const APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.PutJson(APayload);
end;

function TRestClient.PutJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.PutJson(AEndpoint, APayload);
end;

function TRestClient.Header(const AName, AValue: string): TRestClient;
begin
  FInstance.Header(AName, AValue);
  Result := Self;
end;

function TRestClient.Retry(AValue: Integer): TRestClient;
begin
  FInstance.Retry(AValue);
  Result := Self;
end;

function TRestClient.Timeout(AValue: Integer): TRestClient;
begin
  FInstance.Timeout(AValue);
  Result := Self;
end;

function TRestClient.Get(const AEndpoint: string): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteAsync(hmGET, AEndpoint);
end;

function TRestClient.Get<T>(const AEndpoint: string): TAsyncBuilder<T>;
var
  Builder: TAsyncBuilder<IRestResponse>;
begin
  Builder := Get(AEndpoint);
  Result := Builder.ThenBy<T>(
    TFunc<IRestResponse, T>(
      function(LRes: IRestResponse): T
      begin
        Result := TDextJson.Deserialize<T>(LRes.ContentString);
      end
    )
  );
end;

function TRestClient.Post(const AEndpoint: string): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteAsync(hmPOST, AEndpoint);
end;

function TRestClient.Post(const AEndpoint: string; const ABody: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteAsync(hmPOST, AEndpoint, ABody);
end;

function TRestClient.Post<TRes>(const AEndpoint: string; const ABody: TRes): TAsyncBuilder<IRestResponse<TRes>>;
var
  Stream: TStringStream;
  Builder: TAsyncBuilder<IRestResponse>;
begin
  Stream := TStringStream.Create(TDextJson.Serialize(ABody), TEncoding.UTF8);
  Builder := ExecuteAsync(hmPOST, AEndpoint, Stream, True);
  Result := Builder.ThenBy<IRestResponse<TRes>>(
      TFunc<IRestResponse, IRestResponse<TRes>>(
        function(Base: IRestResponse): IRestResponse<TRes>
        begin
          Result := TRestResponse<TRes>.Create(Base.StatusCode, Base.StatusText, Base.ContentStream,
            TDextJson.Deserialize<TRes>(Base.ContentString), Base.GetHeaders);
        end
      )
  );
end;

function TRestClient.Put(const AEndpoint: string): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteAsync(hmPUT, AEndpoint);
end;

function TRestClient.Put(const AEndpoint: string; const ABody: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteAsync(hmPUT, AEndpoint, ABody);
end;

function TRestClient.Put<TRes>(const AEndpoint: string; const ABody: TRes): TAsyncBuilder<IRestResponse<TRes>>;
var
  Stream: TStringStream;
  Builder: TAsyncBuilder<IRestResponse>;
begin
  Stream := TStringStream.Create(TDextJson.Serialize(ABody), TEncoding.UTF8);
  Builder := ExecuteAsync(hmPUT, AEndpoint, Stream, True);
  Result := Builder.ThenBy<IRestResponse<TRes>>(
      TFunc<IRestResponse, IRestResponse<TRes>>(
        function(Base: IRestResponse): IRestResponse<TRes>
        begin
          Result := TRestResponse<TRes>.Create(Base.StatusCode, Base.StatusText, Base.ContentStream,
            TDextJson.Deserialize<TRes>(Base.ContentString), Base.GetHeaders);
        end
      )
  );
end;

function TRestClient.Put<T>(const AEndpoint: string): TAsyncBuilder<T>;
var
  Builder: TAsyncBuilder<IRestResponse>;
begin
  Builder := Put(AEndpoint);
  Result := Builder.ThenBy<T>(
    TFunc<IRestResponse, T>(
      function(LRes: IRestResponse): T
      begin
        Result := TDextJson.Deserialize<T>(LRes.ContentString);
      end
    )
  );
end;

function TRestClient.Delete(const AEndpoint: string): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteAsync(hmDELETE, AEndpoint);
end;

function TRestClient.Delete<T>(const AEndpoint: string): TAsyncBuilder<T>;
var
  Builder: TAsyncBuilder<IRestResponse>;
begin
  Builder := Delete(AEndpoint);
  Result := Builder.ThenBy<T>(
    TFunc<IRestResponse, T>(
      function(LRes: IRestResponse): T
      begin
        Result := TDextJson.Deserialize<T>(LRes.ContentString);
      end
    )
  );
end;

function TRestClient.Query(const AEndpoint: string): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteAsync(hmQUERY, AEndpoint);
end;

function TRestClient.Query(const AEndpoint: string; const ABody: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := ExecuteAsync(hmQUERY, AEndpoint, ABody);
end;

function TRestClient.Query<TRes>(const AEndpoint: string; const ABody: TRes): TAsyncBuilder<IRestResponse<TRes>>;
var
  Stream: TStringStream;
  Builder: TAsyncBuilder<IRestResponse>;
begin
  Stream := TStringStream.Create(TDextJson.Serialize(ABody), TEncoding.UTF8);
  Builder := ExecuteAsync(hmQUERY, AEndpoint, Stream, True);
  Result := Builder.ThenBy<IRestResponse<TRes>>(
      TFunc<IRestResponse, IRestResponse<TRes>>(
        function(Base: IRestResponse): IRestResponse<TRes>
        begin
          Result := TRestResponse<TRes>.Create(Base.StatusCode, Base.StatusText, Base.ContentStream,
            TDextJson.Deserialize<TRes>(Base.ContentString), Base.GetHeaders);
        end
      )
  );
end;

function TRestClient.Query<T>(const AEndpoint: string): TAsyncBuilder<T>;
var
  Builder: TAsyncBuilder<IRestResponse>;
begin
  Builder := Query(AEndpoint);
  Result := Builder.ThenBy<T>(
    TFunc<IRestResponse, T>(
      function(Res: IRestResponse): T
      begin
        Result := TDextJson.Deserialize<T>(Res.ContentString);
      end
    )
  );
end;

function TRestClient.QueryJson(const APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.QueryJson(APayload);
end;

function TRestClient.QueryJson(const AEndpoint, APayload: string): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.QueryJson(AEndpoint, APayload);
end;

function TRestClient.GetInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.GetInto(AEndpoint, AResponseStream);
end;

function TRestClient.PostInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.PostInto(AEndpoint, AResponseStream);
end;

function TRestClient.PutInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.PutInto(AEndpoint, AResponseStream);
end;

function TRestClient.PatchInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.PatchInto(AEndpoint, AResponseStream);
end;

function TRestClient.QueryInto(const AEndpoint: string;
  const AResponseStream: TStream): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.QueryInto(AEndpoint, AResponseStream);
end;

function TRestClient.DownloadToFile(const AEndpoint: string;
  const ATargetFilePath: string; const AProgress: TRestReceiveAnonEvent;
  const AOptions: TRestDownloadOptions): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.DownloadToFile(AEndpoint, ATargetFilePath, AProgress, AOptions);
end;

function TRestClient.OnReceive(const AHandler: TRestReceiveEvent): TRestClient;
begin
  FInstance.OnReceive(AHandler);
  Result := Self;
end;

function TRestClient.OnReceive(const AHandler: TRestReceiveAnonEvent): TRestClient;
begin
  FInstance.OnReceive(AHandler);
  Result := Self;
end;

function TRestClient.Execute(RequestInfo: THttpRequestInfo): TAsyncBuilder<IRestResponse>;
var
  BodyStream: TStringStream;
  Method: TDextHttpMethod;
begin
  if RequestInfo = nil then
    raise Exception.Create('RequestInfo cannot be nil');

  // Map Method String to Enum
  if SameText(RequestInfo.Method, 'GET') then Method := hmGET
  else if SameText(RequestInfo.Method, 'POST') then Method := hmPOST
  else if SameText(RequestInfo.Method, 'PUT') then Method := hmPUT
  else if SameText(RequestInfo.Method, 'DELETE') then Method := hmDELETE
  else if SameText(RequestInfo.Method, 'PATCH') then Method := hmPATCH
  else if SameText(RequestInfo.Method, 'HEAD') then Method := hmHEAD
  else if SameText(RequestInfo.Method, 'OPTIONS') then Method := hmOPTIONS
  else if SameText(RequestInfo.Method, 'QUERY') then Method := hmQUERY
  else raise Exception.Create('Unsupported HTTP Method: ' + RequestInfo.Method);

  // Prepare Body
  BodyStream := nil;
  if RequestInfo.Body <> '' then
    BodyStream := TStringStream.Create(RequestInfo.Body, TEncoding.UTF8);

  // Execute
  Result := ExecuteAsync(Method, RequestInfo.Url, BodyStream, True, RequestInfo.Headers);
end;

function TRestClient.ExecuteAsync(AMethod: TDextHttpMethod; const AEndpoint: string; 
  const ABody: TStream; AOwnsBody: Boolean; AHeaders: IDictionary<string, string>): TAsyncBuilder<IRestResponse>;
begin
  Result := FInstance.ExecuteAsync(AMethod, AEndpoint, ABody, AOwnsBody, AHeaders);
end;


end.
