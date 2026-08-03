# lex-pack-delivery

Last-mile delivery domain pack — VRP-with-time-windows planning (proxies `lex-routing` over HTTP) + proof-of-delivery evidence.

Extracted from [`lex-ev-fleet`](https://github.com/alpibrusl/lex-ev-fleet) (see [issue #238](https://github.com/alpibrusl/lex-ev-fleet/issues/238)). No cross-pack dependency. `lex-routing` is a runtime HTTP backend (configured via `routing_url`), not a `lex.toml` dependency.

## Routes

```
POST /delivery/plan  { depot, stops:[{id,lat,lon,demand,ready,due,service}],
                        capacity, max_vehicles, depot_ready, depot_due, profile }
  -> proxies to lex-routing /vrp, records a `delivery.plan` trail event,
     returns the routed plan { routes, unassigned }.
POST /delivery/pod   { order_id, outcome("delivered"|"failed"), note }
  -> appends a signed `delivery.pod` event to the trail (provable delivery).
```

## Usage

```lex
import "lex-pack-delivery/delivery" as delivery

# in your router-wiring code:
let r := delivery.mount(router.new(), db, routing_url)
```

`delivery.manifest()` returns the `pos.PackManifest` describing this pack's parties/pattern for the `lex-soft/src/positions` catalogue.

## Layering

Part of the lex-soft pack family: `lex-soft` (engine, primitives) → this pack (`mount()` for the HTTP routes, `manifest()` for the `lex-soft/src/positions` catalogue) → [`lex-soft-node`](https://github.com/alpibrusl/lex-soft-node) (mounts a configured set of packs into a running deployment).

## License

Matches the rest of the lex ecosystem.
