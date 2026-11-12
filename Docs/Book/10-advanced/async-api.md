# Async API

Async/Await and real asynchronous programming for Delphi.

## What is TAsyncTask?

`TAsyncTask` is a high-level primitive for managing asynchronous operations without the complexity of manual thread management. It allows task chaining and automatic return to the main thread (UI thread).

## Running a Task

```pascal
uses
  Dext.Core.Async;

TAsyncTask.Run(procedure
  begin
    // This runs in a separate thread (background)
    DoHeavyWork;
  end);
```

## Fluent Chaining

You can chain operations that depend on previous results:

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
      // Executed on UI Thread
      if IsActive then
        UpdateUI;
    end)
  .Start;
```

## Exception Handling

```pascal
TAsyncTask.Run(procedure
  begin
    raise EInvalidOperation.Create('Error in background');
  end)
  .OnException(
    procedure(Ex: Exception)
    begin
      // Catch error on UI Thread
      ShowMessage('Error: ' + Ex.Message);
    end)
  .Start;
```

## Cancellation

Use `TCancellationToken` to abort running tasks:

```pascal
var CTS := TCancellationTokenSource.Create;

TAsyncTask.Run(procedure
  begin
    while not CTS.Token.IsCancellationRequested do
    begin
      // Process...
    end;
  end)
  .Start;

// Later...
CTS.Cancel;
```

---

[← Configuration](configuration.md) | [Next: Appendix →](../appendix/type-system.md)


## Callbacks, Cancellation and Failures

- **Main-thread callbacks** (`OnComplete`, `OnException`, `OnCancelled`) are queued with
  `TThread.Queue`. In a VCL/FMX app the message loop runs them. In a console program, or any
  thread without a message loop, they run only when the main thread calls `CheckSynchronize`.
  `TAsyncTask.WaitPumping(Task, TimeoutMs)` waits for the task while pumping that queue.
  Use `OnCompleteAsync` / `OnExceptionAsync` to run the callback on the worker thread instead.
- **`OnCancelled`** handles a cancelled token (before, during or after the work). It replaces
  `OnException` for cancellations. A cancellation with no handler ends the task quietly.
- **A failure with no `OnException`** is not swallowed: the task records it and `Task.Wait`
  raises `EAggregateException`.
- **`Await`** runs the pipeline synchronously on the calling thread; it is not a non-blocking
  await, and it does not call the callbacks. Exceptions (including `EOperationCancelled`)
  reach the caller.

```pascal
var Task := TAsyncTask.Run<Integer>(LoadTotal)
  .WithCancellation(CTS.Token)
  .OnComplete(procedure(Total: Integer) begin ShowTotal(Total); end)
  .OnCancelled(procedure begin ShowCancelled; end)
  .OnException(procedure(E: Exception) begin ShowError(E.Message); end)
  .Start;

TAsyncTask.WaitPumping(Task, 5000);   // console programs
```
