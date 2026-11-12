# 📦 Generic Collections (`Dext.Collections`)

`Dext.Collections` is the high-performance, memory-safe in-memory data engine
of the **Dext Framework**. Designed from the ground up to solve the main
pain points of standard Delphi generics (`System.Generics.Collections`), it
dramatically reduces **Compilation Time** (via Binary Code Folding) while
delivering **Zero Memory Leaks**, **Lock-Free Concurrency**, and **LINQ**
expressiveness.

---

## 🚀 Why Not Just `System.Generics.Collections`?

Standard Delphi collections impose a heavy tax on modern applications:

1. **Compilation Time & Binary Bloat**: Instantiating hundreds of generic
   lists (`TList<T1>`, `TList<T2>`) forces the compiler to duplicate machine
   code for every type parameter.
2. **Manual Memory Management**: Missing a `.Free` call causes memory leaks,
   especially when passing collections across service boundaries.
3. **Cache Inefficiency**: RTL `TDictionary` uses linked-list bucket chaining,
   causing heavy L1/L2 CPU cache misses.
4. **Lock Contention**: Thread-safe operations in legacy code depend on heavy
   `TCriticalSection` or `TMonitor` locks.

---

## 🏗️ Architecture & Performance Pillars

### 1. Binary Code Folding (`TRawList`, `TRawDictionary`, `TRawOrderedDict`)
Dext uses a thin generic interface frontend (`IList<T>`, `IDictionary<K,V>`,
`IOrderedDictionary<K,V>`) over non-generic raw memory backends. The internal
raw engines handle memory buffers, hashing, probing, and managed type
finalization safely.

> ⚡ **Result**: Reduces generic code duplication by up to 60%, dropping build
> times on large codebases from 9 minutes down to 3.5 minutes!

### 2. Cache-Optimized Probing (`Open Addressing` + `Linear Probing`)
`TRawDictionary` and `TRawOrderedDict` store metadata and entries contiguously
in memory. Searching keys traverses sequential memory addresses, aligning 100%
with modern CPU cache lines and eliminating pointer-chasing cache misses.

### 3. Hardware Acceleration & Zero-Allocations
- **Vector & Span (`Dext.Collections.Vector.pas`)**: Zero-allocation slices for
  high-throughput string/buffer processing.
- **SIMD Vectorization (`Dext.Collections.Simd.pas`)**: Employs AVX/SSE2
  instructions to inspect 16 to 32 bytes per CPU clock cycle.
- **Hybrid Sort (`Dext.Collections.Algorithms.pas`)**: Combines optimized
  `QuickSort` with cache-friendly `Insertion Sort` for small partitions.

---

## 🛠️ Collection Suite Overview

All Dext collections are accessed via interfaces and instantiated through the
`TCollections` factory facade (`Dext.Collections.Factory.pas`).

```pascal
uses
  Dext.Collections;

var
  Users: IList<TUser>;
  Config: IDictionary<string, string>;
  History: IOrderedDictionary<string, TOrder>;
  ReadCache: IFrozenDictionary<string, TProduct>;
  JobQueue: IChannel<TWorkItem>;
begin
  // Object List (Owns and frees objects automatically)
  Users := TCollections.CreateObjectList<TUser>;

  // Dictionary with Case-Insensitive String Keys
  Config := TCollections.CreateDictionaryIgnoreCase<string>;

  // Ordered Dictionary (Insertion-order iteration + O(1) key lookups)
  History := TCollections.CreateOrderedDictionary<string, TOrder>;

  // Lock-Free Concurrent Channel (Go-style with backpressure)
  JobQueue := TChannel<TWorkItem>.CreateBounded(100);
end; // All collections and owned items automatically freed here!
```

---

## 🔒 Memory Safety & Ownership Management

Memory safety is built directly into `IList<T>`, `IDictionary<K,V>`, and
`IOrderedDictionary<K,V>`.

### Object Lists (`OwnsObjects`)
When created via `TCollections.CreateObjectList<T>`, the list takes full
ownership of its items:
- Removing an item automatically destroys it.
- Clearing the list frees all contained objects.
- When the list interface goes out of scope, remaining objects are freed.

```pascal
// Reference-only list (Does NOT destroy objects on remove/clear/destroy)
var RefList := TCollections.CreateList<TUser>(False);
```

### Key/Value Ownership in Dictionaries
`IDictionary` and `IOrderedDictionary` support object ownership for values.
Calling `Extract` hands ownership back to the caller without freeing the object.

---

## 🗂️ New Feature: `IOrderedDictionary<K,V>`

`IOrderedDictionary<K,V>` combines `O(1)` key lookups with dense,
insertion-ordered storage.

### Key Benefits
- **Insertion-Order Enumeration**: Iterating via `for-in` yields elements in the
  exact order they were added (allocation-free enumerator).
- **Positional Access**: Retrieve keys/values by insertion index (`KeyAt`,
  `ValueAt`, `PairAt`, `IndexOf`).
- **Full Comparer & Ownership Support**: Supports custom `IEqualityComparer<K>`,
  case-insensitive string keys, and `OwnsValues`.

```pascal
var Dict := TCollections.CreateOrderedDictionary<string, Integer>;
Dict.Add('First', 10);
Dict.Add('Second', 20);

// Fast positional lookup
Writeln('Item at index 0: ', Dict.KeyAt(0), ' = ', Dict.ValueAt(0));

// Iterates in exact insertion order: 'First', then 'Second'
for var Pair in Dict do
  Writeln(Pair.Key, ': ', Pair.Value);
```

---

## ⚡ Concurrency & Multi-Threading Patterns

Modern backend server applications face bottlenecks when managing concurrent data
(such as user sessions or active web connections). Dext provides three distinct
concurrency models tailored to different workload characteristics:

### 1. `TConcurrentDictionary<K,V>` (Lock Striping / Bucket Locking)
Located in `Dext.Collections.Concurrent.pas`, `TConcurrentDictionary` implements
**Lock Striping** (similar to Intel TBB or Java `ConcurrentHashMap`).

Instead of protecting the entire dictionary with a single global `TCriticalSection`,
it distributes entries across multiple independent spin-lock buckets (`TSpinLock`).
- **High Concurrency**: Writes and lookups to different key buckets execute in
  parallel without blocking each other.
- **Zero Global Contention**: Lock scope is confined strictly to the specific bucket
  being modified.

```pascal
uses
  Dext.Collections.Concurrent;

var
  Sessions: TConcurrentDictionary<string, TSessionList>;
begin
  // Thread-safe lookup with bucket-level lock scoping only
  if Sessions.TryGetValue(SessionId, OutList) then
    ProcessSessions(OutList);
end;
```

### 2. `IFrozenDictionary<K,V>` (Lock-Free Read Operations) 🧊
Located in `Dext.Collections.Frozen.pas`, frozen collections are designed for
read-heavy multi-threaded workloads (e.g., routing tables, cached metadata, session tokens).

1. Build and populate the dictionary during startup or initialization.
2. Call `.ToFrozenDictionary`.
3. Read concurrently from hundreds of threads **100% Lock-Free** without any
   locks (`TCriticalSection` or `TSpinLock`) or memory barrier penalties.

### 3. `IChannel<T>` (Go-Style Message Passing)
Located in `Dext.Collections.Channels.pas`, `IChannel<T>` replaces shared, hand-locked
queues with channels. Each channel guards its queue with a single monitor: it is
thread-safe and blocks efficiently, but it is **not** lock-free.

- **Native Backpressure**: Bounded channels (`TChannel<T>.CreateBounded(1000)`) make a
  fast producer wait (`Write`) or give up (`TryWrite`) instead of exhausting memory.
  The capacity must be at least 1.
- **End of stream**: `Close` stops new writes; items already queued can still be read.
  `Read` on a closed, empty channel raises `EChannelCompletedException`;
  `Write` on a closed channel raises `EChannelClosedException`.
  `IsCompleted` tells you whether anything more can ever be read.
- **Never stuck by design**: `TryRead(Value, TimeoutMs)` and `TryWrite(Value, TimeoutMs)`
  wait a bounded time; `Read(Token)` and `Write(Value, Token)` wake up with
  `EOperationCancelled` when the token is cancelled.

```pascal
var
  Chan: IChannel<TSessionMessage> := TChannel<TSessionMessage>.CreateBounded(1000);

// Producer thread
TTask.Run(procedure
  begin
    Chan.Write(Msg);
    // ... when there is nothing more to send:
    Chan.Close;
  end);

// Consumer thread: drains everything, then stops on its own
TTask.Run(procedure
  begin
    try
      while True do
        SendToNetwork(Chan.Read);
    except
      on EChannelCompletedException do ; // end of stream
    end;
  end);
```

---

## ⚡ LINQ & Expression Filtering

Dext collections feature rich LINQ methods integrated directly into `IList<T>`.

```pascal
var u := Prototype.Entity<TUser>;

// Expressive Spec/Property Filtering (Dext.Specifications)
var Admins := Users
  .Where(u.IsActive and (u.Role = 'Admin'))
  .OrderBy(u.Name.Asc)
  .ToList;

// Functional LINQ Methods
var HasVip := Users.Any(function(User: TUser): Boolean
  begin
    Result := User.IsVip;
  end);
```

---

## 📂 Summary of Dext Collections Units

| Unit Name | Primary Purpose & Responsibilities |
| :--- | :--- |
| `Dext.Collections.pas` | Core interfaces (`IList<T>`, `IDictionary<K,V>`, `IOrderedDictionary<K,V>`, etc.) |
| `Dext.Collections.Factory.pas` | `TCollections` factory facade for clean instantiation |
| `Dext.Collections.Base.pas` | Base implementations (`TSmartList<T>`, `TSmartDictionary<K,V>`) |
| `Dext.Collections.Raw.pas` | Non-generic list backend for code folding (`TRawList`) |
| `Dext.Collections.RawDict.pas` | Non-generic open-addressing dictionary backend (`TRawDictionary`) |
| `Dext.Collections.RawOrderedDict.pas` | Non-generic insertion-ordered dictionary backend (`TRawOrderedDict`) |
| `Dext.Collections.Dict.pas` | Generic `TDictionary<K,V>` frontend wrapper |
| `Dext.Collections.OrderedDict.pas` | Generic `TOrderedDictionary<K,V>` frontend wrapper |
| `Dext.Collections.HashSet.pas` | Set collection interface and open-addressing implementation (`IHashSet<T>`) |
| `Dext.Collections.Frozen.pas` | Read-only lock-free structures (`IFrozenDictionary`, `IFrozenSet`) |
| `Dext.Collections.Channels.pas` | Go-style channel concurrency (`IChannel<T>`) |
| `Dext.Collections.Concurrent.pas` | Thread-safe concurrent queues, stacks, and collections |
| `Dext.Collections.Queue.pas` | Generic Queue data structure (`IQueue<T>`) |
| `Dext.Collections.Stack.pas` | Generic Stack data structure (`IStack<T>`) |
| `Dext.Collections.Vector.pas` | Contiguous zero-allocation dynamic vector & span views |
| `Dext.Collections.Simd.pas` | Hardware-accelerated SIMD search and comparison routines |
| `Dext.Collections.Algorithms.pas` | Hybrid Sort (QuickSort + Insertion Sort) and binary search routines |
| `Dext.Collections.Comparers.pas` | Optimized type-specific equality and hashing comparers |
| `Dext.Collections.Extensions.pas` | Helper extension methods for arrays, enumerables, and LINQ |
| `Dext.Collections.Memory.pas` | Low-level memory utilities and managed type inspection (`IsManagedType`) |
