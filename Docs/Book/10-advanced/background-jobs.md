# Persistent Background Jobs

Persistent Background Jobs allow you to enqueue out-of-process, scheduled, or delayed tasks that survive application crashes and restarts. The engine automatically serializes the job parameters and saves them to a persistent datastore (such as SQLite or In-Memory).

Unlike raw `IHostedService` background tasks, Persistent Background Jobs are resilient, traceable, support automatic retries, and can be configured easily via `appsettings.json`.

---

## Configuration

Configure background jobs in your `appsettings.json`:

```json
{
  "Dext": {
    "BackgroundJobs": {
      "Storage": {
        "Provider": "SQLite", // "SQLite" or "InMemory"
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

## Registration

To enable background jobs, register them in your application startup using `AddBackgroundJobs`:

```pascal
uses
  Dext.DI.Interfaces,
  Dext.BackgroundJobs.Config;

procedure ConfigureServices(const Services: IServiceCollection);
begin
  // Register your job classes in DI
  Services.AddTransient<TEmailService>;

  // Registers job client, storage and the job server (worker pool)
  Services.AddBackgroundJobs;

  // The server runs as a hosted service: add it to the host
  Services.AddBackgroundServices.AddHostedService(TJobServer).Build;
end;
```

Options (all fluent, e.g. `Services.AddBackgroundJobs(procedure(O: TBackgroundJobsOptions) begin ... end)`):

| Option | Default | Meaning |
| :--- | :--- | :--- |
| `Workers(n)` | 4 | Jobs that run at the same time (worker threads). |
| `PollInterval(s)` | 5 | Seconds an idle worker waits before looking for jobs again. |
| `Retries(max, backoff)` | 3, 5 s | Total tries per job (1 = never retry) and the first backoff. |
| `Recovery(heartbeat, orphan)` | 15 s, 120 s | Heartbeat period and the silence after which a Processing job is recovered. |
| `UseQueues([...])` | `default` | Queues polled, in priority order. |


---

## Creating a Job Service

A background job is a method of a class registered in the DI container. The parameters must be simple types serializable to JSON.

```pascal
type
  TEmailService = class
  public
    procedure SendWelcomeEmail(const AEmail: string; const AUserId: Integer);
  end;

procedure TEmailService.SendWelcomeEmail(const AEmail: string; const AUserId: Integer);
begin
  // Send email logic here...
end;
```

---

## Enqueueing and Scheduling Jobs

Initialize the client helper `TDextJobs` and start enqueueing tasks.

### 1. Enqueue Immediately (Fire-and-Forget)

Executes as soon as a background worker becomes available.

```pascal
uses
  Dext.BackgroundJobs.Intf;

// Initialize TDextJobs with Resolved Job Client
var Client := ServiceProvider.GetRequiredService<IJobClient>;
TDextJobs.Initialize(Client);

// Enqueue immediately
var JobId := TDextJobs.Enqueue<TEmailService>('SendWelcomeEmail', ['user@example.com', 123]);
```

### 2. Schedule with a Delay

Executes after the specified time span has passed.

```pascal
uses
  System.TimeSpan,
  Dext.BackgroundJobs.Intf;

// Schedule to execute in 1 hour
var JobId := TDextJobs.Schedule<TEmailService>(
  'SendWelcomeEmail', 
  ['user@example.com', 123], 
  TTimeSpan.FromHours(1)
);
```

---

## Resiliency and Retries

If a job throws an exception during execution, the job server:
1. Records the exception message in the job's `ErrorLog`.
2. Counts the attempt (`AttemptCount`).
3. Retries it with exponential backoff (`RetryBackoffSeconds`, doubling on each retry, capped at one hour) until `MaxAttempts` tries were made; after that the job stays `jsFailed`.
   Retries need a storage that implements `IJobStorageEx` (the InMemory and SQLite providers do); with any other storage a failure is final.

While a job runs, the server records a heartbeat for it. A job left in `jsProcessing` with no heartbeat for `OrphanTimeoutSeconds` (a worker died, or the process was killed) is recovered: it goes back to the queue, counting the lost attempt, or becomes `jsFailed` when no attempts are left.

Each job runs on a fresh instance of its class (constructor-injected from the container) that the server frees afterwards. `Stop` lets running jobs finish (up to the service's `StopTimeoutMs`); jobs are not interrupted.
