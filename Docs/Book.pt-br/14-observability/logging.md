# Logging e Diagnósticos

O Dext possui um sistema de logging robusto, inspirado no ecossistema .NET, que permite registrar mensagens de forma estruturada e direcioná-las para diferentes destinos (Sinks).

## Configuração Básica

O logging é configurado no método `ConfigureServices` da sua classe `Startup` usando o builder fluente:

```pascal
procedure TStartup.ConfigureServices(const Services: TDextServices; const Configuration: IConfiguration);
begin
  Services.AddLogging(
    procedure(Builder: ILoggingBuilder)
    begin
      Builder
        .SetMinimumLevel(TLogLevel.Information)
        .AddConsole
        .AddTelemetry; // Roteia eventos de telemetria para o log
    end);
end;
```

## Níveis de Log

Os seguintes níveis estão disponíveis (em ordem de severidade):

| Nível | Descrição |
| :--- | :--- |
| `Trace` | Logs detalhados para diagnóstico profundo. |
| `Debug` | Logs úteis durante o desenvolvimento. |
| `Information` | Fluxos normais da aplicação (startup, requisições). |
| `Warning` | Eventos anômalos que não interrompem o fluxo. |
| `Error` | Falhas que impedem uma operação específica. |
| `Critical` | Falhas críticas que exigem atenção imediata. |

## Log em Arquivo

O Dext inclui um provedor nativo para gravação em arquivos. Os arquivos são gravados no formato **JSON Lines** por padrão, facilitando o consumo por ferramentas de análise.

```pascal
Builder.AddFile('logs/app.log', 10, True); // Nome, Tamanho Max (MB), Rotação Diária
```

### Rotação de Arquivos (Rolling Files)

O provedor de arquivo do Dext suporta dois mecanismos de rotação automática para evitar que os arquivos de log cresçam indefinidamente:

1.  **Rotação Diária (`ARollDaily`)**: Quando ativado, ao mudar o dia, o arquivo atual (ex: `app.log`) é renomeado para incluir a data (ex: `app-2026-05-14.log`) e um novo arquivo de log é iniciado.
2.  **Rotação por Tamanho (`AMaxFileSizeMB`)**: Se o arquivo atingir o limite definido em Megabytes, ele é rotacionado com um sufixo numérico (ex: `app.001.log`, `app.002.log`) e um novo arquivo limpo é criado.

Você pode combinar ambos os mecanismos para garantir uma política de retenção robusta.

### Segurança e Concorrência (Thread-Safety)

O sistema de logging do Dext é **totalmente thread-safe**. 
- O `TFileSink` utiliza um sistema de trava (`TMonitor`) interna para garantir que múltiplas threads (como requisições HTTP simultâneas) possam logar sem corromper o arquivo ou o buffer.
- As mensagens são acumuladas em um buffer de memória (4KB) antes de serem escritas no disco, reduzindo drasticamente o número de operações de I/O.

### Alta Performance com RingBuffer (Async Logging)

Para aplicações de altíssimo desempenho, onde o tempo de resposta é crítico, o Dext oferece o modo **Async Logging**. Ele utiliza o `RingBuffer` nativo (lock-free) para que a thread da sua aplicação nunca fique bloqueada aguardando o disco ou o console.

```pascal
Services.AddLogging(
  procedure(Builder: ILoggingBuilder)
  begin
    Builder
      .AddAsync // Ativa o modo de alta performance
      .SetMinimumLevel(TLogLevel.Information)
      .AddConsole
      .AddFile('logs/app.log', 10, True);
  end);
```

> [!IMPORTANT]
> Ao ativar o `.AddAsync`, o Dext gerencia automaticamente um pool de buffers e uma thread dedicada para o despacho dos logs, garantindo que o impacto no "Hot Path" da sua aplicação seja praticamente nulo.

> [!TIP]
> O modo síncrono padrão já é extremamente eficiente devido ao buffering interno de 4KB. O modo Async é recomendado para cenários de throughput massivo ou onde latências de microsegundos são importantes.

## O Pipeline Assíncrono e o `Log` Global

O `.AddAsync` e o `Log` global (`Log.Info`, `Log.Error`...) usam o mesmo pipeline, cada um com sua fila e sua thread: quem chama formata a mensagem e a publica numa fila limitada (65.536 entradas); uma thread em segundo plano entrega as entradas aos sinks.

- **Nível mínimo.** Entradas abaixo do nível mínimo são descartadas antes de a mensagem ser formatada. O padrão é `Information`. Com `AddLogging`, o nível vem de `Builder.SetMinimumLevel`; no logger global, use `Log.SetMinimumLevel(TLogLevel.Debug)`.
- **Sem sink, sem trabalho.** Enquanto nenhum sink está registrado, `ILogger.IsEnabled` devolve `False` e a chamada de log retorna na hora. Execuções de teste não têm sink de console, então o log do framework não custa nada nelas.
- **Sem polling.** O consumidor dorme num evento enquanto a fila está vazia, e o produtor só o acorda quando o encontra dormindo: um processo ocioso não gasta CPU com log, e uma entrada chega aos sinks em dezenas de microssegundos.
- **Nunca bloqueia.** Com a fila cheia (um sink lento numa rajada), a entrada é descartada e contada. Os sinks recebem então um `Warning` da categoria `Dext.Logging`: "N log entries dropped: the async queue was full". `TAsyncLoggerFactory.Dropped` guarda o total.
- **Categoria.** `TLogEntry.Category` traz o nome passado ao `CreateLogger`, para sinks que roteiam ou filtram por ela.
- **Sidecar.** O sink do Sidecar vem desligado por padrão e só liga quando configurado (`DEXT_SIDECAR_ENABLED=true` ou `TSidecarOptions.Enabled`). Veja [Dext Dashboard (Sidecar)](../09-cli/dashboard.md).

Um sink próprio implementa `ILogSink`. O `Emit` roda na thread consumidora, então seja breve ou repasse o trabalho:

```pascal
type
  TCountingSink = class(TInterfacedObject, ILogSink)
  private
    FErrors: Integer;
  public
    procedure Emit(const Entry: TLogEntry);
    procedure Flush;
  end;

procedure TCountingSink.Emit(const Entry: TLogEntry);
begin
  if Entry.Level >= TLogLevel.Error then
    TInterlocked.Increment(FErrors);
end;

procedure TCountingSink.Flush;
begin
end;

// Logger global
Log.AddSink(TCountingSink.Create);
```

## Utilizando o ILogger

Para registrar mensagens, você deve solicitar a interface `ILogger` via Injeção de Dependência em seus controladores ou serviços:

```pascal
type
  TMyController = class(TWebController)
  private
    FLogger: ILogger;
  public
    constructor Create(const ALogger: ILogger);
    
    function Get: IWebResponse;
  end;

function TMyController.Get: IWebResponse;
begin
  FLogger.Info('Processando requisição para {Path}', [Request.Path]);
  // ...
end;
```

### Mensagens Estruturadas

O Dext suporta mensagens estruturadas usando a sintaxe de chaves `{}`. Isso permite que provedores avançados (como o Telemetry Bridge) capturem os parâmetros de forma independente da mensagem formatada.

```pascal
FLogger.LogInformation('Pedido {Id} processado com sucesso em {Duration}ms', [LOrderId, LDuration]);
```

## Logging de Requisições HTTP

Para registrar automaticamente todas as requisições HTTP (URL, Método, Status Code, Tempo), adicione o middleware no método `Configure`:

```pascal
procedure TStartup.Configure(const App: IWebApplication);
begin
  App.Builder.UseHttpLogging;
  // ...
end;
```

## Sinks de Log APM (Seq & OpenTelemetry)

O Dext suporta o envio de logs estruturados e telemetria para ferramentas modernas de monitoramento de performance de aplicação (APM). Esses sinks acumulam os logs em uma fila thread-safe na memória e os enviam em lotes (batches) assíncronos usando threads em background, garantindo que a aplicação não sofra gargalos de performance.

Para utilizar os sinks APM, certifique-se de que o seu projeto referencie o pacote `Dext.Net`, onde os clientes de rede de alta performance estão localizados.

### Sink para Seq (Formato CLEF)

O Seq é um servidor popular para visualização de logs estruturados. O Dext envia os logs formatados no padrão Compact Log Event Format (CLEF) via HTTP.

```pascal
Builder.AddSeq('http://localhost:5341', 'sua-chave-api', TBatchOptions.Default.BatchSize(100).FlushInterval(5000));
```

### Sink para OpenTelemetry (OTLP/HTTP)

Para coleta de logs corporativa e tracing distribuído (ex: SigNoz, Datadog ou OpenTelemetry Collector), o Dext implementa o protocolo OTLP/HTTP JSON padrão.

```pascal
Builder.AddOpenTelemetry(
  'http://localhost:4318', 
  'nome-do-servico', 
  'Production',
  True, // Exportar Logs
  False, // Exportar Traces
  TBatchOptions.Default.BatchSize(200).FlushInterval(2000)
);
```

### Configurações de Envio em Lote (TBatchOptions)

Ambos os sinks aceitam uma configuração fluida de `TBatchOptions`:
- `BatchSize(Integer)`: O número máximo de logs acumulados na fila antes que o envio em lote seja disparado automaticamente (padrão: 100).
- `FlushInterval(Integer)`: O intervalo máximo em milissegundos a se esperar antes de disparar o lote, mesmo que o tamanho máximo de logs não tenha sido atingido (padrão: 5000ms).

---

[← Telemetria](observabilidade.md)
