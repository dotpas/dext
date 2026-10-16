# S76: Nullable<T> Uninitialized Local Variables

**Status**: Draft (deferred, to be implemented later)
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

### D. `class operator Initialize` (Delphi 10.4+) — **chosen direction**
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

## 4. Decision
Implement **D**, guarded by a compiler-version directive, and document the
`Clear` rule (option C) for Delphi versions before 10.4.

## 5. Implementation Plan (later)
1. Add `Initialize` to `Nullable<T>` under `{$IF CompilerVersion >= 34.0}`.
2. Add a comment in `Dext.Types.Nullable.pas` documenting the pre-10.4 caveat
   and the `Clear` workaround.
3. Add a unit test: an uninitialized local `Nullable<Int64>` (and `Integer`,
   `Double`, `TDateTime`) must report `IsNull = True`. Run it with the stack
   deliberately dirtied by a prior call to avoid a false pass.
4. Benchmark before/after: hydrate a large list of entities with
   `Nullable<Int64>` properties and compare time and memory (see S18, S57).
5. Run the full unit test suite, especially RTTI/hydration paths that read
   `FHasValue` by offset.
6. Revisit `Issue_192_...` and remove the `Clear` workaround only if the
   test must prove the default state.

## 6. Open Questions
- Is the measured hydration cost of the managed record acceptable? If not,
  fall back to option C plus documentation.
- Does the fast-path hydration (S57) bypass `Initialize` by writing records
  through raw pointers?
- Should `Prop<Nullable<T>>` (S22) get the same treatment?
