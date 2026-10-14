# Serialização e Globalização

O Dext Framework foi projetado para ser "seguro por padrão" ao lidar com a troca de dados entre diferentes regiões (locales) e sistemas. Este capítulo aborda como o Dext gerencia configurações de formato, serialização JSON e parsing de datas.

## Cultura Invariante por Padrão

As funções padrão do Delphi `FloatToStr` e `StrToFloat` utilizam as configurações regionais do SO (ex: usando vírgula `,` como separador decimal no Brasil). Isso pode corromper payloads JSON e consultas SQL que esperam o ponto `.` como separador.

O Dext força o uso de `TFormatSettings.Invariant` em todas as unidades de serialização principais:

- **Serialização JSON**: `Dext.Json` e `Dext.Json.Utf8` sempre usam `.` para números.
- **Headers Web**: Valores de qualidade (`q=0.8`) e datas de expiração de cookies são formatados usando configurações invariantes.
- **Conversões de Banco de Dados**: Conversores de tipo internos priorizam o parsing invariante para evitar erros de "Invalid float" em servidores com diferentes configurações regionais.

## Parsing de Data e Hora

O Dext fornece utilitários robustos para processar datas de várias fontes (headers HTTP, strings JSON, arquivos CSV) através da unidade `Dext.Core.DateUtils`.

### `TryParseCommonDate`

A função `TryParseCommonDate` tenta converter uma string usando uma sequência de formatos:
1. **ISO 8601** (ex: `2025-12-25T10:00:00Z`)
2. **Padrão do Sistema** (Formato atual do Windows/Linux)
3. **Formatos Comuns** (`dd/mm/yyyy`, `mm/dd/yyyy`, `yyyy-mm-dd`)

```pascal
uses Dext.Core.DateUtils;

var
  LDate: TDateTime;
begin
  // ISO 8601
  if TryParseCommonDate('2025-12-25T15:30:00', LDate) then ...
  
  // Específico da região (dd/mm/yyyy ou mm/dd/yyyy dependendo do SO)
  if TryParseCommonDate('25/12/2025', LDate) then ...
end;
```

### Sobrecarga com FormatSettings

A partir da Versão 1.1, você pode passar um `TFormatSettings` específico para o parser se estiver lidando com dados de uma fonte conhecida:

```pascal
var
  GermanFS: TFormatSettings;
begin
  GermanFS := TFormatSettings.Create('de-DE');
  if TryParseCommonDate('25.12.2025', LDate, GermanFS) then
    Log('Data em formato alemão processada!');
end;
```

## Hidratação JSON e Datas

No `TEntityDataSet` e no sistema de mapeamento JSON, o Dext lida automaticamente com conversões de data a partir de strings JSON. Ele utiliza `TryParseISODateTime` internamente, garantindo que:

- Propriedades `TDateTime` recebam o timestamp completo.
- Propriedades `TDate` recebam apenas a parte da data (Trunc).
- Propriedades `TTime` recebam apenas a parte da hora (Frac).

### O formato das datas no JSON

Todos os serializadores (`TDextJson`, o writer UTF-8 `TUtf8JsonWriter`, o deserializador de records usado pelo binding do corpo, as projeções do DbSet) escrevem e leem datas do mesmo jeito, o padrão ISO 8601 / RFC 3339:

| Tipo | Texto JSON |
|---|---|
| `TDateTime` | `"2026-07-15T10:30:00.000+02:00"`: a hora **local** com o seu deslocamento do UTC (`Z` quando o deslocamento é zero) |
| `TDate` | `"2026-07-15"`: o dia do calendário |
| `TTime` | `"10:30:00.000"`: a hora do relógio |

Os dígitos são a hora local do relógio, então um cliente que ignora o deslocamento ainda mostra 10:30; um cliente que o respeita (JavaScript `new Date()`, Java, .NET) obtém o instante certo, também na hora que se repete quando termina o horário de verão.

A leitura aceita `yyyy-mm-dd`, `yyyy-mm-ddThh:nn[:ss[.fff]]` (também com espaço) e uma zona: `Z` ou um deslocamento (`+02:00`, `+0200`, `+02`) é **convertido para a hora local** do servidor; um valor sem zona já é hora local. Os outros formatos que `TryParseCommonDate` conhece continuam aceitos.

As funções são públicas em `Dext.Core.DateUtils`: `FormatJsonDateTime`, `FormatJsonDate`, `FormatJsonTime`, `TryParseJsonDateTime`, `TryParseJsonTime`. O deslocamento do UTC é calculado em minutos inteiros e guardado por dia do calendário, então o sistema é consultado cerca de uma vez por dia, não uma vez por valor.

Para manter o texto anterior (hora local sem zona), use um formato próprio: `TJsonSettings.Default.CustomDateFormat('yyyy-mm-dd"T"hh":"nn":"ss.zzz')`.

## Gerenciamento de Memória (FastMM5)

Para aplicações de alta performance, o Dext inclui suporte nativo ao **FastMM5**. Ele vem habilitado por padrão no pacote `Dext.Core` para garantir performance ideal em requisições web multi-thread e processamento de grandes volumes de JSON.

Para verificar ou alterar essa configuração, consulte `Dext.MM.pas`:

```pascal
{$DEFINE DEXT_USE_FASTMM5} // Habilitado para gerenciamento de memória de nível enterprise
```

---

## Performance JSON: Perfis Arquiteturais

O Dext possui duas arquiteturas de JSON distintas, projetadas para diferentes perfis de performance. Entender essas diferenças é fundamental para escolher a ferramenta certa para o seu cenário.

### 1. Dext DOM (IDextJsonNode)
Este é o motor padrão utilizado por `TDextJson.Serialize/Deserialize`. Ele constrói uma árvore em memória (DOM) da estrutura JSON.

*   **Ideal para**: 99% das aplicações, incluindo APIs REST, arquivos de configuração e manipulação complexa de objetos.
*   **Pontos Fortes**: Alta velocidade de acesso aleatório, API orientada a objetos intuitiva e performance excepcional na localização de propriedades em estruturas profundamente aninhadas.
*   **Uso de Memória**: Proporcional ao tamanho do documento JSON.

### 2. Dext UTF-8 (Low-Level Streaming)
Esta é uma API de streaming de alta performance encontrada no namespace `Dext.Json.Utf8`. Ela opera diretamente sobre fatias de memória bruta (`TByteSpan`).

*   **Ideal para**: Cenários de Big Data, exportação/importação de milhões de registros ou processamento de arquivos de vários gigabytes.
*   **Pontos Fortes**: Processamento **zero-allocation**. Consegue processar volumes massivos de dados com um footprint de memória constante e mínimo, independentemente do tamanho do arquivo.
*   **Trade-offs**: Como é um streaming parser, ele não indexa o documento. Localizar uma propriedade específica requer uma varredura sequencial desde o início do buffer, o que pode ser mais lento em benchmarks de acesso aleatório, mas é irrelevante para throughput sequencial.

---

## Convenções de Mapeamento JSON (CoC)

O Dext segue uma abordagem de **Convenção sobre Configuração (CoC)** para a serialização JSON, otimizada especificamente para lidar com as particularidades do RTTI do Delphi.

### Serialização de Records
O RTTI do Delphi possui limitações no tratamento de propriedades em records durante a manipulação dinâmica de memória. Para garantir uma serialização e deserialização confiável, o Dext segue estas regras:

1.  **Campos Públicos**: Sempre utilize campos (`fields`) públicos para os membros de records que deseja serializar.

```pascal
type
  TUserDTO = record
  public
    id: Integer;
    name: string;
    roles: IList<string>;
  end;
```

2.  **Mapeamento Explícito**: Utilize o atributo `[JsonName]` para desvincular sua convenção de nomenclatura PascalCase das chaves JSON (geralmente camelCase ou snake_case).

```pascal
type
  TUserDTO = record
  public
    [JsonName('id')] Id: Integer;
    [JsonName('full_name')] Name: string;
    [JsonName('roles')] Roles: IList<string>;
  end;
```

> [!IMPORTANT]
> **Evite propriedades em Records** para fins de serialização. Embora o Delphi as suporte, chamadas `SetValue` via RTTI em records muitas vezes operam em cópias temporárias da estrutura, fazendo com que a instância original não seja populada corretamente. Use campos públicos.

### Tratamento de Coleções Genéricas (IList<T>)
Quando o Dext encontra um tipo de interface como `IList<T>` ou `IReadOnlyList<T>`, ele precisa de uma estratégia para instanciar a implementação concreta.

#### 1. Registro via TActivator
Registre o mapeamento entre a interface e sua implementação concreta (geralmente `TList<T>` ou `TSmartList<T>`).

```pascal
initialization
  TActivator.RegisterDefault<IList<TUserDTO>, TList<TUserDTO>>;
```

#### 2. Pré-instanciação (Hidratação)
Se um campo ou propriedade já contiver uma instância (ex: criada em um construtor ou via factory), o Dext irá **detectar e reutilizar** essa instância em vez de tentar criar uma nova.

```pascal
constructor TMyClass.Create;
begin
  // O Dext irá popular esta lista existente durante a deserialização
  FItems := TCollections.CreateList<TItem>; 
end;
```

### O Atributo `[JsonName]`
O atributo `[JsonName]` permite manter seu código Delphi limpo e seguindo os padrões da linguagem, enquanto atende a requisitos externos de APIs.

```pascal
type
  TConfig = record
  public
    [JsonName('max_threads')] MaxThreads: Integer; // Mapeia para "max_threads" no JSON
  end;
```

### O Atributo `[JsonIgnore]`
`[JsonIgnore]` deixa um membro fora do JSON nos dois sentidos: ele não é escrito e não é lido. A leitura importa tanto quanto a escrita: uma classe ou um record preenchido a partir do corpo de uma requisição nunca recebe do cliente um membro ignorado.

Com um `TJsonIgnoreMode` o membro é ignorado em um sentido só:

```pascal
type
  TUser = class
  public
    property Name: string read FName write FName;
    [JsonIgnore]                           // nem escrito nem lido
    property Internal: string read FInternal write FInternal;
    [JsonIgnore(TJsonIgnoreMode.OnWrite)]  // lido, nunca escrito: entra e nunca volta
    property Password: string read FPassword write FPassword;
    [JsonIgnore(TJsonIgnoreMode.OnRead)]   // escrito, nunca lido: quem decide é o servidor
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;
```

O mesmo vale para os campos de records. `[JsonPublishedOnly]` em uma classe também vale nos dois sentidos: só as propriedades published são escritas e lidas.

### Dados Binários (`TBytes`)
O JSON não tem um tipo binário, e a convenção para dados binários é uma **string Base64** (RFC 4648; `format: byte` no OpenAPI). Um `TBytes`, ou qualquer outro array dinâmico de `Byte`, é escrito assim: em uma linha, com padding, em classes, records, arrays, listas e na raiz do JSON.

```pascal
type
  TDocument = class
  public
    property Name: string read FName write FName;
    property Content: TBytes read FContent write FContent;
  end;

// {"Name":"a.png","Content":"iVBORw0KGgo="}
Json := TDextJson.Serialize(Doc);
```

A leitura aceita as formas que outros sistemas escrevem: Base64 padrão, o alfabeto URL (`-` e `_`), sem o `=` final, com quebras de linha MIME; e um array de números de 0 a 255, para que o JSON escrito por versões anteriores continue sendo lido. Um texto que não é Base64, um número fora de 0..255 ou qualquer outro valor gera uma exceção com o nome do campo: dados binários nunca são adivinhados.

Para escrever o array de números (para um cliente que o espera): `TJsonSettings.Default.BytesAsBase64(False)`.

### Atributos de Formato
Quatro atributos mudam a forma como um membro é escrito, em propriedades de classes e campos de records, e o mesmo membro é lido de volta nessa forma:

| atributo | em | escrito como | lido |
|---|---|---|---|
| `[JsonFormat('dd/mm/yyyy')]` | `TDateTime`, `TDate`, `TTime` | o formato, com as configurações invariantes (`/` e `:` como escritos, qualquer que seja o locale) | o formato; também uma data padrão |
| `[JsonString]` | inteiros, floats, `Currency`, `Boolean` | uma string: `"9007199254740993"`, `"12.5"`, `"true"` | uma string ou o valor normal |
| `[JsonNumber]` | `string` | um número; texto vazio é `null`, texto que não é número continua texto | um número ou uma string |
| `[JsonBoolean]` | inteiros | `true`/`false` (0 é `false`) | um Boolean ou um número |

```pascal
type
  TOrder = class
  public
    [JsonString]  // além de 2^53 um número JavaScript perde dígitos
    property Id: Int64 read FId write FId;
    [JsonFormat('yyyymmdd')]
    property Day: TDate read FDay write FDay;
  end;

// {"Id":"9007199254740993","Day":"20260715"}
```

`[JsonFormat]` lê de volta formatos feitos de `yyyy yy mm m dd d hh h nn n ss s zzz z` e texto fixo (`TJsonUtils.TryParseDateWithFormat`). Um formato que não pode ser lido de volta (nomes de meses, `am/pm`), dois desses atributos no mesmo membro, ou um atributo num tipo que ele não pode mudar geram `EDextJsonException` na primeira serialização da classe ou do record: um atributo que não faz nada nunca fica em silêncio.

> [!TIP]
> Use o **Dext DOM** para o desenvolvimento diário de suas APIs. Mude para o **Dext UTF-8** apenas quando o consumo de memória se tornar um gargalo ou quando estiver processando fluxos massivos de dados.

---

[← Tópicos Avançados](README.md)
