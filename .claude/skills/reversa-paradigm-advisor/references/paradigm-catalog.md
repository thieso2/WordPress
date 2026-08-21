> Local copy of the advisory catalog. The canonical source lives in `templates/migration/catalogs/paradigm_catalog.md`.
> This copy is installed alongside the agent so it has access to the catalog inside the user's project, without depending on the npm package's location.

# Paradigm Catalog (local copy)

## Paradigm catalog

### Procedural
- **Characteristics**: top-level functions, linear flow in controllers, no classes or purely ornamental ones, data as dicts/structs, open side effects.
- **Legacy examples**: classic PHP scripts, COBOL batch, pre-OO Perl systems, shell scripts.
- **Signals in `_reversa_sdd/`**: the domain described as "functions", linear flows in `process_flows`, no explicit aggregates.

### Classic OO
- **Characteristics**: class hierarchy, heavy inheritance, Active Record pattern, logic coupled to the models, the framework dictating structure.
- **Legacy examples**: monolithic Rails, traditional Django, pre-DI Java EE, .NET WebForms / classic.
- **Signals in `_reversa_sdd/`**: classes with broad responsibilities, inheritance in the domain model, anemic controllers calling model methods.

### OO with DI
- **Characteristics**: injection containers, explicit interfaces, Repository / Service pattern, clear separation between layers.
- **Legacy examples**: modern Spring, .NET 6+, NestJS, modern Symfony.
- **Signals in `_reversa_sdd/`**: explicit aggregates, repository interfaces, no Active Record.

### Functional
- **Characteristics**: immutability dominant, pure functions, composition, no implicit side effects, rich typing.
- **Legacy examples**: Haskell, Elm, F#, functional Scala, Clojure.
- **Signals in `_reversa_sdd/`**: algebraic types, no classes, flow expressed as composition.

### Event-driven (asynchronous)
- **Characteristics**: queues / topics, decoupled handlers, no linear flow, eventual consistency, explicit idempotency.
- **Legacy examples**: modern queue-oriented Node backends, SQS / Kafka-heavy systems, asynchronous microservices.
- **Signals in `_reversa_sdd/`**: events in the domain model, integrations via queues, long-running processes with retry.

### Actor model
- **Characteristics**: isolated actors with a mailbox, supervision, state isolation.
- **Legacy examples**: Erlang / Elixir / OTP, Akka.
- **Signals in `_reversa_sdd/`**: supervised processes, messages between actors.

### Dataflow
- **Characteristics**: declarative pipelines, streaming transformations, no imperative loops in the domain.
- **Legacy examples**: classic ETLs, Spark, Flink.
- **Signals in `_reversa_sdd/`**: DAG-shaped descriptions, staged transformations.

## Stack → natural paradigm mapping

| Target stack | Natural paradigm | Viable alternatives | Notes |
|---|---|---|---|
| Node.js 20 (Fastify, Express, NestJS) | asynchronous event-driven | OO with DI (NestJS), light functional | async-first runtime; heavy CPU blocking goes to worker threads |
| Go (net/http, Echo, Fiber) | CSP / goroutines (light event-driven) | structured procedural | concurrency via channels; OO simulated through interfaces |
| Rust (axum, Actix, tokio) | ownership / async functional | event-driven | immutability by default, safety through types |
| Elixir / Phoenix | actor model (BEAM) | functional | supervision via OTP |
| Modern Python (FastAPI, Django 5) | OO with DI or rich procedural | event-driven (Celery, asyncio) | the choice depends on the framework |
| Kotlin (Spring Boot, Ktor) | OO with DI | event-driven (Reactor) | coroutines make async ergonomic |
| .NET 8 (ASP.NET Core, Minimal API) | OO with DI | event-driven (Channels, MediatR) | OO tradition + first-class asynchrony |
| Modern Java (Spring Boot 3, Quarkus) | OO with DI | event-driven (Project Reactor) | functional libraries possible but not dominant |
| Modern Ruby (Rails 7, Hanami) | classic OO (Rails) or OO with DI (Hanami) | light functional (dry-rb) | Rails dictates Active Record; Hanami is DI-heavy |
| Serverless TypeScript (AWS Lambda, Cloudflare Workers) | event-driven | functional | event-triggered invocation; cold start influences the design |

## Table of typical gaps per pair

| From → To | Main gap | Concrete implications |
|---|---|---|
| procedural → event-driven | synchrony → asynchrony | the response stops being immediate; error handling becomes retry/DLQ; idempotency becomes mandatory; event ordering starts to matter |
| procedural → OO with DI | data as dicts → aggregates | invariants move inside aggregates; logic stops living in controllers; dependencies via interfaces |
| procedural → functional | open side effects → pure + isolated | mutability becomes the exception; composition replaces sequencing; algebraic types for states |
| classic OO → event-driven | synchronous flow → choreography | actions stop being atomic; distributed transactions become sagas; strong consistency → eventual |
| classic OO → OO with DI | inheritance → composition via interfaces | Active Record disappears; persistence becomes a repository; tests gain natural mocks |
| classic OO → functional | mutable encapsulation → immutability | methods with effects become pure functions + explicit updates; state expressed as a sequence of transformations |
| OO with DI → event-driven | synchronous command → event | the return stops being immediate; orchestration becomes choreography; ordering per key |
| OO with DI → functional | mocks → testable composition | DI stops being interface-based and becomes function-argument-based |
| functional → event-driven | synchronous composition → messaging | latency increases; failure becomes a message in a DLQ; state becomes distributed |
| event-driven → synchronous procedural | unnatural; only makes sense for small systems | collapse handlers into direct calls; loss of decoupling; strong consistency returns |
| dataflow → event-driven | declarative DAG → mutable choreography | control becomes less predictable; ordering must be guaranteed per key |
| actor model → OO with DI | messages between actors → synchronous calls | loss of failure isolation; supervision must become try/catch or orchestrated retry |
