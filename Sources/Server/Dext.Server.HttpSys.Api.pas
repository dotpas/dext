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
{  Created: 2026-06-17                                                      }
{                                                                           }
{  Windows HTTP Server API (http.sys) headers and structures mapping.       }
{                                                                           }
{***************************************************************************}
unit Dext.Server.HttpSys.Api;

{$ALIGN 8}
{$MINENUMSIZE 4}

interface

{$MINENUMSIZE 4}

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;

const
  HTTPAPI_DLL = 'httpapi.dll';

  HTTP_INITIALIZE_SERVER = $00000001;
  HTTP_INITIALIZE_CONFIG = $00000002;

  // HttpReceiveRequest flags
  HTTP_RECEIVE_REQUEST_FLAG_COPY_BODY = $00000001;

  // HttpReceiveRequestEntityBody flags
  HTTP_RECEIVE_REQUEST_ENTITY_BODY_FLAG_FILL_BUFFER = $00000001;

  // HttpSendHttpResponse flags
  HTTP_SEND_RESPONSE_FLAG_DISCONNECT     = $00000001;
  HTTP_SEND_RESPONSE_FLAG_MORE_DATA      = $00000002;
  HTTP_SEND_RESPONSE_FLAG_BUFFER_DATA    = $00000004;
  HTTP_SEND_RESPONSE_FLAG_OPAQUE         = $00000040;

  // Request flags
  HTTP_REQUEST_FLAG_MORE_ENTITY_BODY_EXISTS = $00000001;
  HTTP_REQUEST_FLAG_IP_ROUTED               = $00000002;
  HTTP_REQUEST_FLAG_HTTP2                   = $00000004;

type
  ULONG = Cardinal;
  USHORT = Word;
  UCHAR = Byte;
  PUCHAR = ^Byte;
  HTTP_OPAQUE_ID = UInt64;
  HTTP_REQUEST_ID = HTTP_OPAQUE_ID;
  HTTP_CONNECTION_ID = HTTP_OPAQUE_ID;
  HTTP_RAW_CONNECTION_ID = HTTP_OPAQUE_ID;
  HTTP_URL_GROUP_ID = HTTP_OPAQUE_ID;
  HTTP_SERVER_SESSION_ID = HTTP_OPAQUE_ID;
  HTTP_URL_CONTEXT = HTTP_OPAQUE_ID;

  HTTPAPI_VERSION = record
    HttpApiMajorVersion: USHORT;
    HttpApiMinorVersion: USHORT;
  end;

  HTTP_VERSION = record
    MajorVersion: USHORT;
    MinorVersion: USHORT;
  end;

  THttpVerb = (
    HttpVerbUnparsed,
    HttpVerbUnknown,
    HttpVerbInvalid,
    HttpVerbOPTIONS,
    HttpVerbGET,
    HttpVerbHEAD,
    HttpVerbPOST,
    HttpVerbPUT,
    HttpVerbDELETE,
    HttpVerbTRACE,
    HttpVerbCONNECT,
    HttpVerbTRACK,
    HttpVerbMOVE,
    HttpVerbCOPY,
    HttpVerbPROPFIND,
    HttpVerbPROPPATCH,
    HttpVerbMKCOL,
    HttpVerbLOCK,
    HttpVerbUNLOCK,
    HttpVerbSEARCH,
    HttpVerbMaximum
  );

  HTTP_COOKED_URL = record
    FullUrlLength: USHORT;     // in bytes not including the #0
    HostLength: USHORT;        // in bytes not including the #0
    AbsPathLength: USHORT;     // in bytes not including the #0
    QueryStringLength: USHORT; // in bytes not including the #0
    pFullUrl: PWideChar;
    pHost: PWideChar;
    pAbsPath: PWideChar;
    pQueryString: PWideChar;
  end;

  PNetAddr = Pointer; // Placeholder for sock address representation

  HTTP_TRANSPORT_ADDRESS = record
    pRemoteAddress: PNetAddr;
    pLocalAddress: PNetAddr;
  end;

  HTTP_UNKNOWN_HEADER = record
    NameLength: USHORT;
    RawValueLength: USHORT;
    pName: PAnsiChar;
    pRawValue: PAnsiChar;
  end;
  PHTTP_UNKNOWN_HEADER = ^HTTP_UNKNOWN_HEADER;
  THTTP_UNKNOWN_HEADER_ARRAY = array[0..65535] of HTTP_UNKNOWN_HEADER;
  PHTTP_UNKNOWN_HEADER_ARRAY = ^THTTP_UNKNOWN_HEADER_ARRAY;

  HTTP_KNOWN_HEADER = record
    RawValueLength: USHORT;
    pRawValue: PAnsiChar;
  end;
  PHTTP_KNOWN_HEADER = ^HTTP_KNOWN_HEADER;

  // HTTP Server API response headers index (0..29)
  // Low(THttpApiHeader)..reqUserAgent for requests (0..40)
  THttpApiHeader = (
    reqCacheControl,
    reqConnection,
    reqDate,
    reqKeepAlive,
    reqPragma,
    reqTrailer,
    reqTransferEncoding,
    reqUpgrade,
    reqVia,
    reqWarning,
    reqAllow,
    reqContentLength,
    reqContentType,
    reqContentEncoding,
    reqContentLanguage,
    reqContentLocation,
    reqContentMd5,
    reqContentRange,
    reqExpires,
    reqLastModified,
    reqAccept,
    reqAcceptCharset,
    reqAcceptEncoding,
    reqAcceptLanguage,
    reqAuthorization,
    reqCookie,
    reqExpect,
    reqFrom,
    reqHost,
    reqIfMatch,
    reqIfModifiedSince,
    reqIfNoneMatch,
    reqIfRange,
    reqIfUnmodifiedSince,
    reqMaxForwards,
    reqProxyAuthorization,
    reqReferer,
    reqRange,
    reqTe,
    reqTranslate,
    reqUserAgent,
    respCacheControl = 0,
    respConnection = 1,
    respDate = 2,
    respKeepAlive = 3,
    respPragma = 4,
    respTrailer = 5,
    respTransferEncoding = 6,
    respUpgrade = 7,
    respVia = 8,
    respWarning = 9,
    respAllow = 10,
    respContentLength = 11,
    respContentType = 12,
    respContentEncoding = 13,
    respContentLanguage = 14,
    respContentLocation = 15,
    respContentMd5 = 16,
    respContentRange = 17,
    respExpires = 18,
    respLastModified = 19,
    respAcceptRanges = 20,
    respAge = 21,
    respEtag = 22,
    respLocation = 23,
    respProxyAuthenticate = 24,
    respRetryAfter = 25,
    respServer = 26,
    respSetCookie = 27,
    respVary = 28,
    respWwwAuthenticate = 29
  );

  HTTP_REQUEST_HEADERS = record
    UnknownHeaderCount: USHORT;
    pUnknownHeaders: PHTTP_UNKNOWN_HEADER;
    TrailerCount: USHORT;
    pTrailers: Pointer;
    KnownHeaders: array[0..40] of HTTP_KNOWN_HEADER; // array matching size of request headers (0..40)
  end;

  HTTP_RESPONSE_HEADERS = record
    UnknownHeaderCount: USHORT;
    pUnknownHeaders: PHTTP_UNKNOWN_HEADER;
    TrailerCount: USHORT;
    pTrailers: Pointer;
    KnownHeaders: array[0..29] of HTTP_KNOWN_HEADER; // array matching size of response headers (0..29 = 30 elements)
  end;

  HTTP_SSL_CLIENT_CERT_INFO = record
    CertFlags: ULONG;
    CertEncodedSize: ULONG;
    pCertEncoded: PUCHAR;
    Token: THandle;
    CertDeniedByMapper: Boolean;
  end;
  PHTTP_SSL_CLIENT_CERT_INFO = ^HTTP_SSL_CLIENT_CERT_INFO;

  HTTP_SSL_INFO = record
    ServerCertKeySize: USHORT;
    ConnectionKeySize: USHORT;
    ServerCertIssuerSize: ULONG;
    ServerCertSubjectSize: ULONG;
    pServerCertIssuer: PAnsiChar;
    pServerCertSubject: PAnsiChar;
    pClientCertInfo: PHTTP_SSL_CLIENT_CERT_INFO;
    SslClientCertNegotiated: ULONG;
  end;
  PHTTP_SSL_INFO = ^HTTP_SSL_INFO;

  HTTP_REQUEST_INFO = record
    InfoType: ULONG;
    pInfo: Pointer;
  end;
  PHTTP_REQUEST_INFO = ^HTTP_REQUEST_INFO;
  PHTTP_REQUEST_INFOS = ^HTTP_REQUEST_INFO;

  HTTP_REQUEST = record
    Flags: ULONG;
    ConnectionId: HTTP_CONNECTION_ID;
    RequestId: HTTP_REQUEST_ID;
    UrlContext: HTTP_URL_CONTEXT;
    Version: HTTP_VERSION;
    Verb: THttpVerb;
    UnknownVerbLength: USHORT;
    RawUrlLength: USHORT;
    pUnknownVerb: PAnsiChar;
    pRawUrl: PAnsiChar;
    CookedUrl: HTTP_COOKED_URL;
    Address: HTTP_TRANSPORT_ADDRESS;
    Headers: HTTP_REQUEST_HEADERS;
    BytesReceived: UInt64;
    EntityChunkCount: USHORT;
    pEntityChunks: Pointer;
    RawConnectionId: HTTP_RAW_CONNECTION_ID;
    pSslInfo: PHTTP_SSL_INFO;
    // Padding and request info for HTTP_REQUEST_V2
    RequestInfoCount: USHORT;
    pRequestInfo: PHTTP_REQUEST_INFOS;
  end;
  PHTTP_REQUEST = ^HTTP_REQUEST;

  THttpChunkType = (
    hctFromMemory,
    hctFromFileHandle,
    hctFromFragmentCache
  );

  HTTP_DATA_CHUNK_INMEMORY = record
    DataChunkType: THttpChunkType;
    Reserved1: ULONG;
    pBuffer: Pointer;
    BufferLength: ULONG;
    {$IFDEF CPUX64}
    Reserved2: array[0..2] of ULONG;
    {$ELSE}
    Reserved2: array[0..3] of ULONG;
    {$ENDIF}
  end;
  PHTTP_DATA_CHUNK_INMEMORY = ^HTTP_DATA_CHUNK_INMEMORY;

  /// <summary>
  ///   Represents a range of bytes within a file.
  /// </summary>
  HTTP_BYTE_RANGE = record
    /// <summary>Starting offset of the range.</summary>
    StartingOffset: ULARGE_INTEGER;
    /// <summary>Length of the range in bytes.</summary>
    Length: ULARGE_INTEGER;
  end;

  /// <summary>
  ///   Represents a data chunk from a file handle for http.sys transmission.
  /// </summary>
  HTTP_DATA_CHUNK_FILEHANDLE = record
    /// <summary>The type of data chunk (always hctFromFileHandle).</summary>
    DataChunkType: THttpChunkType;
    /// <summary>The byte range of the file to transmit.</summary>
    ByteRange: HTTP_BYTE_RANGE;
    /// <summary>The file handle.</summary>
    FileHandle: THandle;
  end;
  PHTTP_DATA_CHUNK_FILEHANDLE = ^HTTP_DATA_CHUNK_FILEHANDLE;

  HTTP_DATA_CHUNK = record
    case DataChunkType: THttpChunkType of
      hctFromMemory: (
        pBuffer: Pointer;
        BufferLength: ULONG;
        {$IFDEF CPUX64}
        Reserved2: array[0..2] of ULONG;
        {$ELSE}
        Reserved2: array[0..3] of ULONG;
        {$ENDIF}
      );
      hctFromFileHandle: (
        ByteRange: HTTP_BYTE_RANGE;
        FileHandle: THandle;
      );
  end;
  PHTTP_DATA_CHUNK = ^HTTP_DATA_CHUNK;

  HTTP_RESPONSE = record
    Flags: ULONG;
    Version: HTTP_VERSION;
    StatusCode: USHORT;
    ReasonLength: USHORT;
    pReason: PAnsiChar;
    Headers: HTTP_RESPONSE_HEADERS;
    EntityChunkCount: USHORT;
    pEntityChunks: Pointer;
    ResponseInfoCount: USHORT;
    pResponseInfo: Pointer;
  end;
  PHTTP_RESPONSE = ^HTTP_RESPONSE;

  HTTP_SERVER_PROPERTY = (
    HttpServerAuthenticationProperty,
    HttpServerLoggingProperty,
    HttpServerQosProperty,
    HttpServerTimeoutsProperty,
    HttpServerQueueLengthProperty,
    HttpServerStateProperty,
    HttpServer503VerbosityProperty,
    HttpServerBindingProperty,
    HttpServerExtendedAuthenticationProperty,
    HttpServerListenEndpointProperty,
    HttpServerChannelBindProperty,
    HttpServerProtectionLevelProperty,
    HttpServerDelegationProperty,
    HttpServerFastForwardingProperty
  );

  HTTP_PROPERTY_FLAGS = ULONG;

  HTTP_ENABLED_STATE = (
    HttpEnabledStateActive,
    HttpEnabledStateInactive
  );

  HTTP_STATE_INFO = record
    Flags: HTTP_PROPERTY_FLAGS;
    State: HTTP_ENABLED_STATE;
  end;
  PHTTP_STATE_INFO = ^HTTP_STATE_INFO;

  HTTP_QOS_SETTING_TYPE = (
    HttpQosSettingTypeBandwidth,
    HttpQosSettingTypeConnectionLimit,
    HttpQosSettingTypeFlowRate
  );

  HTTP_QOS_SETTING_INFO = record
    QosType: HTTP_QOS_SETTING_TYPE;
    QosSetting: Pointer;
  end;

  HTTP_CONNECTION_LIMIT_INFO = record
    Info: HTTP_QOS_SETTING_INFO;
    Flags: HTTP_PROPERTY_FLAGS;
    MaxConnections: ULONG;
  end;
  PHTTP_CONNECTION_LIMIT_INFO = ^HTTP_CONNECTION_LIMIT_INFO;

  HTTP_BINDING_INFO = record
    Flags: HTTP_PROPERTY_FLAGS;
    RequestQueueHandle: THandle;
  end;
  PHTTP_BINDING_INFO = ^HTTP_BINDING_INFO;

const
  HTTPAPI_VERSION_1: HTTPAPI_VERSION = (HttpApiMajorVersion: 1; HttpApiMinorVersion: 0);
  HTTPAPI_VERSION_2: HTTPAPI_VERSION = (HttpApiMajorVersion: 2; HttpApiMinorVersion: 0);

// Windows API functions imported from httpapi.dll
function HttpInitialize(Version: HTTPAPI_VERSION; Flags: ULONG; pReserved: Pointer): ULONG; stdcall; external HTTPAPI_DLL;
function HttpTerminate(Flags: ULONG; pReserved: Pointer): ULONG; stdcall; external HTTPAPI_DLL;

function HttpCreateServerSession(Version: HTTPAPI_VERSION; var ServerSessionId: HTTP_SERVER_SESSION_ID; Reserved: ULONG): ULONG; stdcall; external HTTPAPI_DLL;
function HttpCloseServerSession(ServerSessionId: HTTP_SERVER_SESSION_ID): ULONG; stdcall; external HTTPAPI_DLL;

function HttpCreateUrlGroup(ServerSessionId: HTTP_SERVER_SESSION_ID; var UrlGroupId: HTTP_URL_GROUP_ID; Reserved: ULONG): ULONG; stdcall; external HTTPAPI_DLL;
function HttpCloseUrlGroup(UrlGroupId: HTTP_URL_GROUP_ID): ULONG; stdcall; external HTTPAPI_DLL;

function HttpAddUrlToUrlGroup(UrlGroupId: HTTP_URL_GROUP_ID; pFullyQualifiedUrl: PWideChar; UrlContext: HTTP_URL_CONTEXT; Reserved: ULONG): ULONG; stdcall; external HTTPAPI_DLL;
function HttpRemoveUrlFromUrlGroup(UrlGroupId: HTTP_URL_GROUP_ID; pFullyQualifiedUrl: PWideChar; Flags: ULONG): ULONG; stdcall; external HTTPAPI_DLL;

function HttpCreateRequestQueue(Version: HTTPAPI_VERSION; pName: PWideChar; pSecurityAttributes: Pointer; Flags: ULONG; var ReqQueueHandle: THandle): ULONG; stdcall; external HTTPAPI_DLL;
function HttpCloseRequestQueue(ReqQueueHandle: THandle): ULONG; stdcall; external HTTPAPI_DLL;

function HttpReceiveHttpRequest(ReqQueueHandle: THandle; RequestId: HTTP_REQUEST_ID; Flags: ULONG; pRequestBuffer: PHTTP_REQUEST; RequestBufferLength: ULONG; var BytesReturned: ULONG; pOverlapped: POverlapped): ULONG; stdcall; external HTTPAPI_DLL;
function HttpReceiveRequestEntityBody(ReqQueueHandle: THandle; RequestId: HTTP_REQUEST_ID; Flags: ULONG; pBuffer: Pointer; BufferLength: ULONG; var BytesReceived: ULONG; pOverlapped: POverlapped): ULONG; stdcall; external HTTPAPI_DLL;

function HttpSendHttpResponse(ReqQueueHandle: THandle; RequestId: HTTP_REQUEST_ID; Flags: ULONG; pHttpResponse: PHTTP_RESPONSE; pReserved1: Pointer; var BytesSent: ULONG; pReserved2: Pointer; Reserved3: ULONG; pOverlapped: POverlapped; pLogData: Pointer): ULONG; stdcall; external HTTPAPI_DLL;
function HttpSendResponseEntityBody(ReqQueueHandle: THandle; RequestId: HTTP_REQUEST_ID; Flags: ULONG; EntityChunkCount: USHORT; pEntityChunks: Pointer; var BytesSent: ULONG; pReserved1: Pointer; pReserved2: Pointer; pOverlapped: POverlapped; pLogData: Pointer): ULONG; stdcall; external HTTPAPI_DLL;

type
  HTTP_SERVICE_CONFIG_ID = (
    HttpServiceConfigIPListenList,  // Set, Query & Delete.
    HttpServiceConfigSslCertInfo,
    HttpServiceConfigUrlAclInfo,
    HttpServiceConfigTimeout,
    HttpServiceConfigMax
  );

  SOCKADDR = record
    sa_family: WORD;
    sa_data: array[0..13] of AnsiChar;
  end;

  SOCKADDR_IN = record
    sin_family: WORD;
    sin_port: WORD;
    sin_addr: ULONG;
    sin_zero: array[0..7] of AnsiChar;
  end;
  PSOCKADDR_IN = ^SOCKADDR_IN;

  SOCKADDR_STORAGE = record
    ss_family: WORD;
    __ss_pad1: array[0..5] of Byte;
    __ss_align: Int64;
    __ss_pad2: array[0..111] of Byte;
  end;
  PSOCKADDR_STORAGE = ^SOCKADDR_STORAGE;

  HTTP_SERVICE_CONFIG_SSL_KEY = record
    pIpPort: Pointer;
  end;

  HTTP_SERVICE_CONFIG_SSL_PARAM = record
    CertHashLength: ULONG;
    pCertHash: Pointer;
    AppId: TGUID;
    pCertStoreName: PWideChar;
    CertCheckMode: DWORD;
    RevocationFreshnessTime: DWORD;
    RevocationUrlRetrievalTimeout: DWORD;
    pSslCtlIdentifier: PWideChar;
    pSslCtlStoreName: PWideChar;
    DefaultFlags: DWORD;
  end;

  HTTP_SERVICE_CONFIG_SSL_SET = record
    KeyDesc: HTTP_SERVICE_CONFIG_SSL_KEY;
    ParamDesc: HTTP_SERVICE_CONFIG_SSL_PARAM;
  end;
  PHTTP_SERVICE_CONFIG_SSL_SET =
    ^HTTP_SERVICE_CONFIG_SSL_SET;

  HTTP_SERVICE_CONFIG_QUERY_TYPE = (
    HttpServiceConfigQueryExact,
    HttpServiceConfigQueryNext,
    HttpServiceConfigQueryMax
  );

  HTTP_SERVICE_CONFIG_SSL_QUERY = record
    QueryDesc: HTTP_SERVICE_CONFIG_QUERY_TYPE;
    KeyDesc: HTTP_SERVICE_CONFIG_SSL_KEY;
    dwToken: DWORD;
  end;

function HttpSetServiceConfiguration(ServiceHandle: THandle; ConfigId: DWORD; pConfigInformation: Pointer; ConfigInformationLength: ULONG; pOverlapped: Pointer): ULONG; stdcall; external HTTPAPI_DLL;
function HttpDeleteServiceConfiguration(ServiceHandle: THandle; ConfigId: DWORD; pConfigInformation: Pointer; ConfigInformationLength: ULONG; pOverlapped: Pointer): ULONG; stdcall; external HTTPAPI_DLL;
function HttpQueryServiceConfiguration(ServiceHandle: THandle; ConfigId: DWORD;
  pInputConfigInfo: Pointer; InputConfigInfoLength: ULONG;
  pOutputConfigInfo: Pointer; OutputConfigInfoLength: ULONG;
  var pReturnLength: ULONG; pOverlapped: Pointer): ULONG; stdcall; external HTTPAPI_DLL;
function HttpSetUrlGroupProperty(UrlGroupId: HTTP_URL_GROUP_ID; PropertyId: HTTP_SERVER_PROPERTY; pPropertyInformation: Pointer; PropertyInformationLength: ULONG): ULONG; stdcall; external HTTPAPI_DLL;
{$ENDIF}

implementation

end.
