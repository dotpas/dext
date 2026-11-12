unit Dext.RateLimiting.Tests;

interface

uses
  System.Classes,
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.RateLimiting.Core,
  Dext.RateLimiting.Limiters;

type
  [TestFixture('Rate limiters')]
  TRateLimitersTests = class
  public
    [Test('Fixed window denies above the limit and counts each key apart')]
    procedure FixedWindowLimitsPerKey;

    [Test('Fixed window forgets idle keys with no explicit Cleanup call')]
    procedure FixedWindowCleansItself;

    [Test('Sliding window forgets idle keys with no explicit Cleanup call')]
    procedure SlidingWindowCleansItself;

    [Test('Token bucket allows a burst up to its capacity')]
    procedure TokenBucketBurst;

    [Test('Concurrency limiter gives the slot back on Release')]
    procedure ConcurrencyRelease;

    [Test('Fixed window keeps counting while new keys keep arriving')]
    procedure FixedWindowKeepsActiveKeys;
  end;

implementation

{ TRateLimitersTests }

procedure TRateLimitersTests.FixedWindowLimitsPerKey;
var
  LLimiter: IRateLimiter;
begin
  LLimiter := TFixedWindowLimiter.Create(2, 60);
  Should(LLimiter.TryAcquire('a').IsAllowed).BeTrue;
  Should(LLimiter.TryAcquire('a').IsAllowed).BeTrue;
  Should(LLimiter.TryAcquire('a').IsAllowed).BeFalse;
  Should(LLimiter.TryAcquire('b').IsAllowed).BeTrue;
end;

procedure TRateLimitersTests.FixedWindowCleansItself;
var
  LLimiter: TFixedWindowLimiter;
  LHolder: IRateLimiter;
  I: Integer;
begin
  LLimiter := TFixedWindowLimiter.Create(5, 1);
  LHolder := LLimiter;
  for I := 1 to 300 do
    LHolder.TryAcquire('k' + IntToStr(I));
  Should(LLimiter.EntryCount).Be(300);
  // Idle keys are removed after two windows (whole seconds).
  TThread.Sleep(3200);
  for I := 1 to 400 do
    LHolder.TryAcquire('active');
  Should(LLimiter.EntryCount).Be(1);
end;

procedure TRateLimitersTests.SlidingWindowCleansItself;
var
  LLimiter: TSlidingWindowLimiter;
  LHolder: IRateLimiter;
  I: Integer;
begin
  LLimiter := TSlidingWindowLimiter.Create(5, 1);
  LHolder := LLimiter;
  for I := 1 to 300 do
    LHolder.TryAcquire('k' + IntToStr(I));
  Should(LLimiter.EntryCount).Be(300);
  TThread.Sleep(3200);
  for I := 1 to 400 do
    LHolder.TryAcquire('active');
  Should(LLimiter.EntryCount).Be(1);
end;

procedure TRateLimitersTests.TokenBucketBurst;
var
  LLimiter: IRateLimiter;
begin
  LLimiter := TTokenBucketLimiter.Create(3, 1);
  Should(LLimiter.TryAcquire('a').IsAllowed).BeTrue;
  Should(LLimiter.TryAcquire('a').IsAllowed).BeTrue;
  Should(LLimiter.TryAcquire('a').IsAllowed).BeTrue;
  Should(LLimiter.TryAcquire('a').IsAllowed).BeFalse;
end;

procedure TRateLimitersTests.ConcurrencyRelease;
var
  LLimiter: IRateLimiter;
begin
  LLimiter := TConcurrencyLimiter.Create(1);
  Should(LLimiter.TryAcquire('a').IsAllowed).BeTrue;
  Should(LLimiter.TryAcquire('a').IsAllowed).BeFalse;
  LLimiter.Release('a');
  Should(LLimiter.TryAcquire('a').IsAllowed).BeTrue;
end;

procedure TRateLimitersTests.FixedWindowKeepsActiveKeys;
var
  LLimiter: IRateLimiter;
  I, LAllowed: Integer;
begin
  // The periodic cleanup must never drop a key that is still inside its window.
  LLimiter := TFixedWindowLimiter.Create(100, 60);
  LAllowed := 0;
  for I := 1 to 500 do
  begin
    LLimiter.TryAcquire('other' + IntToStr(I));
    if LLimiter.TryAcquire('busy').IsAllowed then
      Inc(LAllowed);
  end;
  Should(LAllowed).Be(100);
end;

end.
