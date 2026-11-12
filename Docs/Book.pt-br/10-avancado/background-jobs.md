# Persistent Background Jobs

Persistent Background Jobs permitem que você enfileire tarefas assíncronas (fora do processo principal, agendadas ou atrasadas) que sobrevivem a travamentos da aplicação e reinicializações. O motor serializa automaticamente os parâmetros do método e os salva em um banco de dados persistente (como SQLite ou In-Memory).

Diferente de tarefas simples em background com `IHostedService`, os Persistent Background Jobs são resilientes, monitoráveis, suportam retentativas automáticas e podem ser configurados facilmente via `appsettings.json`.

---

## Configuração

Configure os parâmetros dos jobs no arquivo `appsettings.json`:

```json
{
  "Dext": {
    "BackgroundJobs": {
      "Storage": {
        "Provider": "SQLite", // "SQLite" ou "InMemory"
        "ConnectionString": "DataSource=dext_jobs.db"
      },
      "Server": {
        "WorkerCount": 4,
        "PollIntervalInSeconds": 5
      }
    }
  }
}
```

---

## Registro

Para habilitar a execução de background jobs, registre o motor no startup da aplicação usando `AddBackgroundJobs`:

```pascal
uses
  Dext.DI.Interfaces,
  Dext.BackgroundJobs.Config;

procedure ConfigureServices(const Services: IServiceCollection);
begin
  // Registre as classes dos seus jobs no DI
  Services.AddTransient<TEmailService>;

  // Registra o cliente, o storage e o servidor de jobs (pool de workers)
  Services.AddBackgroundJobs;

  // O servidor roda como hosted service: adicione-o ao host
  Services.AddBackgroundServices.AddHostedService(TJobServer).Build;
end;
```

Opções (todas fluentes, ex.: `Services.AddBackgroundJobs(procedure(O: TBackgroundJobsOptions) begin ... end)`):

| Opção | Padrão | Significado |
| :--- | :--- | :--- |
| `Workers(n)` | 4 | Jobs que executam ao mesmo tempo (threads de trabalho). |
| `PollInterval(s)` | 5 | Segundos que um worker ocioso espera antes de procurar jobs de novo. |
| `Retries(max, backoff)` | 3, 5 s | Total de tentativas por job (1 = nunca repetir) e o primeiro backoff. |
| `Recovery(heartbeat, orphan)` | 15 s, 120 s | Período do heartbeat e o silêncio após o qual um job em Processing é recuperado. |
| `UseQueues([...])` | `default` | Filas consultadas, em ordem de prioridade. |


---

## Criando um Serviço de Job

Um background job é um método público de uma classe registrada no container DI. Os parâmetros do método devem ser tipos simples serializáveis para JSON (números, strings, booleanos).

```pascal
type
  TEmailService = class
  public
    procedure SendWelcomeEmail(const AEmail: string; const AUserId: Integer);
  end;

procedure TEmailService.SendWelcomeEmail(const AEmail: string; const AUserId: Integer);
begin
  // Lógica de envio de e-mail aqui...
end;
```

---

## Enfileirando e Agendando Tarefas

Inicialize o helper de cliente `TDextJobs` e comece a enfileirar as tarefas.

### 1. Enfileirar Imediatamente (Fire-and-Forget)

Executa o job assim que uma thread livre do worker pool estiver disponível.

```pascal
uses
  Dext.BackgroundJobs.Intf;

// Inicializa a fachada com a instância do cliente resolvida no DI
var Client := ServiceProvider.GetRequiredService<IJobClient>;
TDextJobs.Initialize(Client);

// Enfileira para execução imediata
var JobId := TDextJobs.Enqueue<TEmailService>('SendWelcomeEmail', ['user@example.com', 123]);
```

### 2. Agendar com Atraso (Delay)

Executa o job após o término do período de tempo especificado.

```pascal
uses
  System.TimeSpan,
  Dext.BackgroundJobs.Intf;

// Agenda para ser executado daqui a 1 hora
var JobId := TDextJobs.Schedule<TEmailService>(
  'SendWelcomeEmail', 
  ['user@example.com', 123], 
  TTimeSpan.FromHours(1)
);
```

---

## Resiliência e Falhas

Se uma exceção for lançada durante a execução de um job, o servidor de jobs:
1. Grava a mensagem da exceção no `ErrorLog` do job.
2. Conta a tentativa (`AttemptCount`).
3. Repete o job com backoff exponencial (`RetryBackoffSeconds`, dobrando a cada tentativa, no máximo 1 hora) até completar `MaxAttempts` tentativas; depois disso o job fica `jsFailed`.
   As repetições exigem um storage que implemente `IJobStorageEx` (os provedores InMemory e SQLite implementam); com outro storage a falha é definitiva.

Enquanto um job executa, o servidor registra um heartbeat para ele. Um job que ficou em `jsProcessing` sem heartbeat por `OrphanTimeoutSeconds` (um worker morreu ou o processo foi encerrado) é recuperado: volta para a fila, contando a tentativa perdida, ou vira `jsFailed` se não restarem tentativas.

Cada job executa em uma instância nova da sua classe (com injeção pelo construtor a partir do container), que o servidor libera depois. `Stop` deixa os jobs em execução terminarem (até o `StopTimeoutMs` do serviço); os jobs não são interrompidos.
