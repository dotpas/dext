# S76: Nullable<T> Uninitialized Local Variables

**Status**: Draft (deferred). Option D is on hold after field evidence (see 3.1); option C is the current rule
**Authors**: Cesar Romero, Antigravity
**Date**: 2026-10-16
**Related**: S22 (Prop<T> and Nullable<T> Convergence), issue #267 (found while adding its regression tests)

## 1. Abstract
`Nullable<T>` stores its state in a plain `FHasValue: Boolean`. For value types
without managed fields (`Int64`, `Integer`, `Double`, `TDateTime`, ...) the
record has no managed content, so Delphi does **not** zero-initialize local
variables of this type. A local `Nullable<Int64>` can therefore start as
"has value" with a garbage payload. This spec documents the problem, the
alternatives and the chosen direction.

## 2. The Problem

```pascal
var
  Empty: Nullable<Int64>;      // local, never assigned
begin
  Should(Empty.IsNull).BeTrue; // flaky: depends on stack contents
end;
```

Observed in `Issue_192_FireDAC_Param_Binding_Should_Not_Truncate_Int64`
(`Dext.Entity.ReportedIssues.Tests.pas`): the variable reported
`HasValue = True` with `Value = 355181013653921572`. The test only passed when
the stack slot happened to be zero. The test was patched with an explicit
`EmptyNullable.Clear` as a workaround; the framework type is unchanged.

Scope of the issue:
- Affects only **locals** (globals, class fields and heap objects are zeroed).
- Affects every `T` that is not managed. `Nullable<string>` is safe because
  the `string` field forces the compiler to initialize the whole record.
- Current definition: `Dext.Types.Nullable.pas`, `FValue: T; FHasValue: Boolean;`.
- `FHasValue` is also read through RTTI as a 1-byte `Boolean`
  (`FHasValueOffset` / `PBoolean`), so changing its type has side effects.

## 3. Alternatives

### A. Spring4D style: `FHasValue: string` + `HasValue` as function
The marker is a constant literal (e.g. `'@'`) and `HasValue` is
`FHasValue <> ''`.

- Pros: fixes all Delphi versions; well-known pattern.
- Cons:
  - No heap allocation (literals are not ref-counted, assignment copies a
    pointer), but the record becomes **managed**: `_InitializeRecord`,
    `_CopyRecord` and `_FinalizeRecord` on every copy, assignment and scope
    exit. This is the real cost, mainly in hydration loops and large lists.
  - Record grows by 4 (Win32) / 8 (Win64) bytes instead of 1 (plus padding).
  - `HasValue` stops being a plain field; RTTI-based code (`FHasValueOffset`)
    must be rewritten.

### B. Keep API, make the field managed (`string` / `IInterface`)
Same runtime cost as A, but keeps `property HasValue: Boolean`.

- Pros: public API unchanged.
- Cons: same managed-record overhead as A; RTTI code still needs changes.

### C. Keep `Boolean`, require `Clear` / `Default()` on locals
- Pros: zero framework change, zero cost.
- Cons: remains a trap for every user; failures are intermittent. Only
  acceptable as a documented rule.

### D. `class operator Initialize` (Delphi 10.4+) — **on hold, see 3.1**
Make `Nullable<T>` a custom managed record and zero `FHasValue` in
`Initialize`, keeping `FHasValue: Boolean` and `FValue: T`.

```pascal
{$IF CompilerVersion >= 34.0} // Delphi 10.4 Sydney
class operator Initialize(out Dest: Nullable<T>);
{$IFEND}

{$IF CompilerVersion >= 34.0}
class operator Nullable<T>.Initialize(out Dest: Nullable<T>);
begin
  Dest.FHasValue := False;
end;
{$IFEND}
```

- Pros: public API unchanged; field stays a 1-byte `Boolean`, so the RTTI
  access in `Dext.Types.Nullable.pas` keeps working; fixes the problem for
  every `T`; the extra work is writing one byte.
- Cons:
  - The record becomes managed for the compiler, so some copy/finalize
    overhead appears (expected to be smaller than option A/B, **not yet
    measured**).
  - Only Delphi 10.4+. Older compilers keep the current behavior and need
    option C. The `{$IF CompilerVersion >= 34.0}` guard is kept so the code
    still compiles on older versions, with a documented warning in the unit.
  - Must be checked against code that relies on `Nullable<T>` being a plain
    (non-managed) record, such as `FillChar`/`Move` based paths, `TArray` and
    `IList` storage, and fast-path ORM hydration (see S57).

### 3.1. Field evidence against D (Stefano, 2026-10-16)
An external framework with the same layout (`FValue: T; FHasValue: Boolean`)
tried exactly option D (an `Initialize` that only sets `FHasValue := False`)
and backed it out twice:

- May: access violation ("Read of address 0x8") in a batch UPDATE path that
  builds parameter arrays by reading entity fields by offset, using `Move`.
- Re-checked on current code (1,676-test suite): with the same one-line
  `Initialize`, the test executable dies at startup with runtime error 217
  (access violation) before running any test. The exact spot was not chased;
  the change was the only difference.

Cause: once the record is managed, the compiler adds initialize/finalize/copy
calls, and code that treats records or fields as raw bytes (`Move`,
`FillChar`, offset-based reads and writes, arrays of records filled by memory
copy) stops matching what the compiler expects. The reporter chose option C.

This confirms the risk already listed under D and shows it is not only
theoretical: Dext also reads `FHasValue` by RTTI offset
(`Dext.Types.Nullable.pas`) and has ORM fast paths (S57).

## 4. Decision
Option **C** is the current rule: `Nullable<T>` stays a plain record and locals
are cleared explicitly (`X.Clear`), documented in the Book. Option **D** is
**on hold**. It may only be reconsidered if the validation in section 5 passes.

## 5. Validation Required Before Any Attempt at D
1. Add `Initialize` under `{$IF CompilerVersion >= 34.0}` on a branch only.
2. Run the full unit test suite first; a startup crash (runtime error 217) is
   a blocker.
3. Audit every place that handles `Nullable<T>` or entity fields as raw
   memory: `Move`, `FillChar`, offset-based reads and writes, arrays of
   records filled by memory copy, the `FHasValueOffset` RTTI access, and the
   ORM fast paths (S57).
4. Benchmark before/after, covering the ORM fast paths and not only plain
   hydration (see S18, S57).
5. Check that third-party code doing the same keeps working. The reporter
   offered to run the branch against their 1,676-test suite.
6. Add a unit test: an uninitialized local `Nullable<Int64>` (and `Integer`,
   `Double`, `TDateTime`) must report `IsNull = True`, with the stack
   deliberately dirtied by a prior call to avoid a false pass.

## 6. Open Questions
- Is it worth changing the type at all, given that C has zero cost and no
  surprises in offset-based hot paths?
- Does the fast-path hydration (S57) bypass `Initialize` by writing records
  through raw pointers?
- Should `Prop<Nullable<T>>` (S22) get the same treatment?
- Could a static check (compiler hint, lint or review rule) flag a local
  `Nullable<T>` that is read before `Clear`?
