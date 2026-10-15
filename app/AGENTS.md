# Dartvel

These are the working rules for `rtn_app`. The block below is written by `dartvel dev` and matched to the Dartvel version you have installed; text outside it is yours and is never touched.

<!-- dartvel:begin agents -->
<!-- Written by `dartvel dev`, matched to Dartvel 0.12.2.
     Edits inside this block are replaced; text outside it is kept. -->

## Dartvel 0.12.2

# Dartvel working rules

These are the rules a coding agent must follow when writing Dartvel
application code. They describe the API as this version of Dartvel has it.

A rule here is not advice. Each one names something that compiles, or does
not, or that a reviewer will reject. Where Dartvel offers one way to do
something, the second way is not a matter of taste: it is wrong for every
storage engine that is not the one it was written for.

## Application code imports the barrel, not the generated siblings

Every page imports the generated barrel:

```dart
import '../dartvel_client/dartvel_client.dart';
```

Generated models, routes, widgets and client functions all arrive from there.
Importing a generated sibling file directly couples the application to a file
name the generator owns and can rename.

## Data models are the only way data is written

```dart
final Order order = Order(id: id, total: total);
await order.save();

final DVSearchResultPage<Order> pending = await Order.search('pending', perPage: 20);

await order.delete();
```

Never write through a record operation, a table or column name, a database
adapter the application constructs, or a SQL string. Dartvel is
storage-neutral: SQL, Firestore, MongoDB and DynamoDB sit behind the same
models, so an API that takes a record shape is wrong for every engine that is
not SQL.

The record operations exist as the framework's contract with its engines. They
are not imported by an application and do not appear in a page.

## A model's capabilities are members of the model

```dart
await Article.search('dartvel');
await Article.importCsv(csvText);      // also importNdjson and importExcel
await Article.semanticSearch('what is a model');
```

Do not generate or refer to a companion class per model. No `ArticleSearch`,
no `ArticleImport`, no `<Model>Anything`. If a sample has to name one of them
to make sense, the model's surface is missing something.

## Routes are typed

```dart
DVRoutes.article.withId(id);
DVRoutes.signin.withQuery({'from': DVRoutes.account.path});
```

A path written out as a string drifts the moment the page moves, and nothing
fails when it does. A generated target turns that into a compile error. A
module's pages are typed too, through `DV.Modules.<id>Routes`.

## Generation inputs are private

```dart
@DVModel() class const _Order({required final String id, final int total = 0});
```

Annotation inputs begin with `_`. Application code references the generated
public API -- `Order`, `Order.Form(...)`, the generated widgets, the generated
routes -- never the annotated declaration.

## Forms save themselves

```dart
Order.Form()             // creates a record
order.Form()             // edits that record
```

`Model.Form(...)` takes no callback. Policies decide whether the reader may
create or edit, as they do everywhere else. A form does not ask the
application to wire up its own save.

## Signals are signals

```dart
final total = context.signal(0);
total.value++;
final doubled = total * 2;   // a signal that tracks total
final payable = (stock > 0) & agreed;   // stock and agreed are signals; so is the result
```

An operation on signals returns a signal that tracks its sources. There is no
separate derived-value constructor: the result of operating on signals is
already one, and it composes because of that. `context.signal(...)`,
`signal(context, value)`, reactive models and `DV.global` are the whole
surface.

## One generator

`dartvel routes` writes the whole client. `dartvel build` and `dartvel dev` run
it before anything else, so a normal project never invokes it by hand.

There is no `build_runner` and no `build.yaml` in an application. A project
that declares `build_runner` and has no builders pays for a build that
generates nothing, on every build.

## Native integrations are FFI and JNI

Native libraries are bound through FFI/ffigen. Android and JVM APIs through
JNI/jnigen. No `MethodChannel`, `EventChannel` or `BasicMessageChannel`.

Flutter-facing APIs stay stable under `DV.Platform.*`; generated native
bindings adapt behind that surface.

## Style: primary constructors and dot shorthands

```dart
class const Layout({super.key, required super.child}) extends DartvelLayout {
  @override
  Widget build(BuildContext context) => DVBox.list([child]);
}
```

```dart
DVBox.list([
  DVText('Total'),
], mainAxisAlignment: .center, padding: const .all(8));
```

Where the context type makes a shorthand valid, use it: the type is already on
the parameter. Where the context type is `Object` or `dynamic`, or does not
declare the member, write the type out.

## Read this project's own reference too

`dartvel docs` builds a reference from this project's graph: its routes, data
models, backend functions, jobs, policies and modules. It is more accurate than
any document written for every project, because it is about this one.

## What is not in the application surface

The framework's own machinery stays out of application code: transports and
carriers for model sync, `DVModelSync`, `DVSemanticIndex`, `DVOfflineRemote`,
`DVCacheRuntime`, the lifecycle registries behind `DV.lifecycle`, the worker
behind `DV.Jobs.work(...)`, and the platform bindings that report connectivity.
An application reads the signal and waits; it does not drive the machinery.
<!-- dartvel:end agents -->

## MyRTN in this repository

How this app applies the rules above, and where Dartvel 0.12.2 leaves a gap.

- `lib/main.dart` is the smallest main 0.12.2 can run, with a TODO to become `DV.run()` when
  Dartvel ships it.
- Pages are one line in `lib/pages/**`; screens are `@DVFunctionalWidget`s in `lib/components/`.
  No `StatelessWidget`, `StatefulWidget`, `Text` or `Container` in app code: `DVBox`, `DVText`
  and signals. Async data sits in a `DVSignal<Reply<T>?>` filled by `loadInto` (`lib/services/remote.dart`).
  A functional widget's body is moved into generated code, so it may only refer to public names.
- Every control has a tooltip, and the tooltip is its accessible name: start it with the visible
  label (`ActionButton` does this for you). Never put `semanticLabel` on text that shows a value;
  it replaces the value for screen readers.
- A `DVBox.row` with no `Flexible` child becomes a wrapping bar on narrow screens. A `Spacer` is
  not a `Flexible`: use `Expanded(child: SizedBox.shrink())`.
- Backend functions are typed: they take strings, ints and bools and return `Reply<T>` from
  `lib/services/wire.dart`, never a map and never a thrown error (Dartvel turns those into a bare
  500). `wire.dart` is the only place JSON is written; a page passes `fromJson: Reply.of(T.fromJson)`
  because the 0.12.2 client asks for it.
- Access is `@DVBackendFunction(policy: 'SubscriberLine.view' | 'OperatorConsole.update' ...)`,
  defined in `lib/policies/access.dart`. 0.12.2 has no `middleware:` field on the annotation, and
  `DVMiddlewares.auth` refuses everything unless the server is wired for it, so policies are the gate.
  The line a function acts on is the session's user id (`me(ctx)`), never a request field.
- Sign-in is a phone number and a code the RTN core sends by SMS; `lib/server/sessions.dart`
  turns a checked code into a Dartvel session. Those two functions take the `Request`, so their
  client calls are the only ones that name fields (`lib/services/account.dart`).
- `/my/**` and `/console/**` have `_guard.dart`s; `/`, `/signin` and `/operator` are public. A
  `_guard.dart` directly in `lib/pages` would guard the sign-in page too.
- Server-only code is in `lib/server/` (dart:io, dart:ffi). Pages never import it.
- Text the core writes (ledger notes, SMS, bundle names, refusals) is decoded with `words()` in
  `wire.dart`, which turns its `234…` numbers into the local `0999 000 0001` form.
- `DVBox.wrapLine`, not its compatibility alias `DVBox.wrap`. Format with `dart format .` (page
  width 120, set in `analysis_options.yaml`).
- `FocusKeeper` (`lib/services/focus.dart`) works around a 0.12.2 web bug where the page shell
  takes focus from a control, so Tab could not get past the top bar; remove it when Dartvel fixes it.

Tests: `flutter test` (the services tests load `../core/target/release/librtn_ffi.so`; build it
with `cargo build --release` in `core/`). Build: `dartvel build web-server` (set `DARTVEL_CHROME`
when Chrome is not in a standard place).
