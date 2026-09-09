{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Agent - Multi-Provider LLM Agent                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    TLLMFactory resolves the correct ILLMProvider from a config string,    }
{    the same idea as LangChain's init_chat_model('provider:model').        }
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
unit Dext.AI.Agent.Factory;

interface

uses
  Dext.AI.Agent.Contracts;

type
  TLLMFactory = class
  public
    // Cria o provider correto baseado em ProviderString
    // Exemplos:
    //   'openai:gpt-4o'
    //   'openai:gpt-4-turbo'
    //   'anthropic:claude-sonnet-4-6'
    //   'anthropic:claude-haiku-4-5'
    //   'ollama:llama3.2'
    //   'ollama:mistral'
    class function CreateProvider(const AConfig: TAgentConfig): ILLMProvider;

    // Parse do ProviderString ? (ProviderName, ModelName)
    class procedure ParseProviderString(
      const AProviderString: string;
      out AProvider, AModel: string
    );
  end;

implementation

uses
  System.SysUtils,
  Dext.AI.Agent.Provider.OpenAI,
  Dext.AI.Agent.Provider.Anthropic,
  Dext.AI.Agent.Provider.Ollama;

class procedure TLLMFactory.ParseProviderString(
  const AProviderString: string;
  out AProvider, AModel: string
);
var
  Parts: TArray<string>;
begin
  Parts := AProviderString.Split([':']);
  if Length(Parts) >= 1 then
    AProvider := Parts[0].ToLower
  else
    AProvider := '';

  if Length(Parts) >= 2 then
    AModel := Parts[1]
  else
    AModel := '';
end;

class function TLLMFactory.CreateProvider(const AConfig: TAgentConfig): ILLMProvider;
var
  ProviderName, ModelName: string;
begin
  ParseProviderString(AConfig.ProviderString, ProviderName, ModelName);

  if ProviderName = 'openai' then
  begin
    if ModelName = '' then ModelName := 'gpt-4o';
    Result := TOpenAIProvider.Create(AConfig.ApiKey, ModelName, AConfig.MaxTokens);
  end
  else if ProviderName = 'anthropic' then
  begin
    if ModelName = '' then ModelName := 'claude-sonnet-4-6';
    Result := TAnthropicProvider.Create(AConfig.ApiKey, ModelName, AConfig.MaxTokens);
  end
  else if ProviderName = 'ollama' then
  begin
    if ModelName = '' then ModelName := 'llama3.2';
    var BaseUrl := AConfig.BaseUrl;
    if BaseUrl = '' then BaseUrl := 'http://localhost:11434';
    Result := TOllamaProvider.Create(BaseUrl, ModelName, AConfig.MaxTokens);
  end
  else
    raise ELLMProviderError.CreateFmt(
      'Provider desconhecido: "%s". Use: openai, anthropic ou ollama.',
      [ProviderName]
    );
end;

end.
