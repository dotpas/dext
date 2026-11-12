# API Assíncrona

Async/Await e programação assíncrona real para Delphi.

## O que é TAsyncTask?

`TAsyncTask` é uma primitiva de alto nível para gerenciar operações assíncronas sem a complexidade de gerenciar threads manualmente. Ela permite o encadeamento de tarefas e o retorno automático para a thread principal (UI thread).

## Executando uma Tarefa

```pascal
uses
  Dext.Core.Async;

TAsyncTask.Run(procedure
  begin
    // Isso roda em uma thread separada (background)
    FazerTrabalhoPesado;
  end);
```

## Encadeamento de Tarefas (Fluent Chaining)

Você pode encadear operações que dependem do resultado da anterior:

```pascal
TAsyncTask.Run<TUserProfile>(
  function: TUserProfile
  begin
    Result := ApiService.GetProfile(UserId);
  end)
  .ThenBy<Boolean>(
    function(Profile: TUserProfile): Boolean
    begin
      Result := Profile.IsActive;
    end)
  .OnComplete(
    procedure(IsActive: Boolean)
    begin
      // Executado na UI Thread
      if IsActive then
        UpdateUI;
    end)
  .Start;
```

## Tratamento de Exceções

```pascal
TAsyncTask.Run(procedure
  begin
    raise EInvalidOperation.Create('Erro no background');
  end)
  .OnException(
    procedure(Ex: Exception)
    begin
      // Captura o erro na UI Thread
      ShowMessage('Erro: ' + Ex.Message);
    end)
  .Start;
```

## Cancelamento

Use `TCancellationToken` para abortar tarefas em execução:

```pascal
var CTS := TCancellationTokenSource.Create;

TAsyncTask.Run(procedure
  begin
    while not CTS.Token.IsCancellationRequested do
    begin
      // Processar...
    end;
  end)
  .Start;

// Mais tarde...
CTS.Cancel;
```

---

[← Configuração](configuracao.md) | [Próximo: Apêndice →](../apendice/sistema-tipos.md)


## Callbacks, Cancelamento e Falhas

- **Callbacks na thread principal** (`OnComplete`, `OnException`, `OnCancelled`) entram na fila
  com `TThread.Queue`. Em VCL/FMX o loop de mensagens os executa. Em um programa console, ou em
  qualquer thread sem loop de mensagens, eles só rodam quando a thread principal chama
  `CheckSynchronize`. `TAsyncTask.WaitPumping(Task, TimeoutMs)` espera a tarefa processando
  essa fila. Use `OnCompleteAsync` / `OnExceptionAsync` para executar o callback na thread de
  trabalho.
- **`OnCancelled`** trata um token cancelado (antes, durante ou depois do trabalho) e substitui
  `OnException` nos cancelamentos. Um cancelamento sem tratador termina a tarefa em silêncio.
- **Uma falha sem `OnException`** não é engolida: a tarefa a registra e `Task.Wait` levanta
  `EAggregateException`.
- **`Await`** executa o pipeline de forma síncrona na thread chamadora; não é um await não
  bloqueante e não chama os callbacks. As exceções (inclusive `EOperationCancelled`) chegam ao
  chamador.

```pascal
var Task := TAsyncTask.Run<Integer>(LoadTotal)
  .WithCancellation(CTS.Token)
  .OnComplete(procedure(Total: Integer) begin ShowTotal(Total); end)
  .OnCancelled(procedure begin ShowCancelled; end)
  .OnException(procedure(E: Exception) begin ShowError(E.Message); end)
  .Start;

TAsyncTask.WaitPumping(Task, 5000);   // programas console
```
