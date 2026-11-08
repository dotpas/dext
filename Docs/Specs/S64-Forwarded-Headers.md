# Spec S64: Forwarded Headers Middleware (`TForwardedHeadersMiddleware`)

- **Status**: Implemented / Released (V1.0)
- **Autor**: Antigravity & Cezar
- **Data**: 2026-08-10
- **Módulo**: `Dext.Web.ForwardedHeaders` (`Sources/Web/Dext.Web.ForwardedHeaders.pas`)

---

## 1. Contexto e Objetivos

Em ambientes de produção com proxies reversos (Nginx, Traefik, AWS ALB, IIS), o cliente se conecta ao proxy e o proxy encaminha a requisição ao servidor Dext via HTTP interno. Isso faz com que o servidor Dext veja o IP do proxy em vez do IP real do cliente, e o esquema como `http` em vez de `https`.

O ecossistema .NET resolve isso via `UseForwardedHeaders()`.

### Objetivos:
1. Criar `TForwardedHeadersMiddleware` para inspecionar e aplicar os cabeçalhos:
   - `X-Forwarded-For`: Atualiza o IP do cliente (`Req.RemoteIP`).
   - `X-Forwarded-Proto`: Atualiza o esquema (`http`/`https`).
   - `X-Forwarded-Host`: Atualiza o Host original solicitado.
2. Suportar lista de proxies confiáveis (*KnownProxies* e *KnownNetworks*).
3. Evitar falsificação de IP (*IP Spoofing*) rejeitando cabeçalhos de proxies não confiáveis.

---

## 2. Design da API

```pascal
type
  TForwardedHeadersOptions = class
  private
    FKnownProxies: TList<string>;
    FForwardedHeaders: TForwardedHeadersFlags;
  public
    constructor Create;
    destructor Destroy; override;
    property KnownProxies: TList<string> read FKnownProxies;
    property ForwardedHeaders: TForwardedHeadersFlags read FForwardedHeaders write FForwardedHeaders;
  end;

// Extensão no AppBuilder
procedure UseForwardedHeaders(App: IAppBuilder; ConfigureOptions: TProc<TForwardedHeadersOptions> = nil);
```

---

## 3. Exemplo de Uso

```pascal
App.UseForwardedHeaders(
  procedure(Opts: TForwardedHeadersOptions)
  begin
    Opts.KnownProxies.Add('127.0.0.1');
    Opts.KnownProxies.Add('10.0.0.0/8');
  end);
```

## 4. Complementos de segurança e protocolo

### 4.1 Cadeia de confiança

`X-Forwarded-For` pode conter uma lista separada por vírgulas. O middleware
deve processar a cadeia da direita para a esquerda, removendo somente saltos
que pertençam a `KnownProxies` ou `KnownNetworks`. O primeiro endereço fora da
cadeia confiável é o endereço efetivo do cliente.

Não se deve aceitar `X-Forwarded-*` quando a conexão imediata não vier de uma
origem confiável. A configuração padrão deve ser segura: nenhum proxy
confiável e nenhum cabeçalho aplicado.

### 4.2 Opções necessárias

Adicionar opções para:

- `ForwardLimit`;
- `KnownNetworks` em CIDR para IPv4 e IPv6;
- política para cabeçalhos ausentes ou inválidos;
- `RequireHeaderSymmetry`;
- habilitar individualmente `For`, `Proto` e `Host`;
- preservar os valores originais em metadados da requisição.

O parser deve validar IPs e CIDRs sem confiar em `StrToInt` ou em comparação
textual. IPv4-mapped IPv6 e portas no valor de `Host` devem ser tratados.

### 4.3 Ordem no pipeline e testes

O middleware deve executar antes de autenticação, autorização, geração de
URLs, rate limiting e logging de auditoria. Testes obrigatórios:

- proxy confiável com uma e várias camadas;
- proxy não confiável tentando forjar o IP;
- IPv4, IPv6 e CIDR;
- `Proto=https` e `Host` original;
- cabeçalhos duplicados, inválidos ou acima do limite;
- ausência de cabeçalhos, mantendo o endereço da conexão.
