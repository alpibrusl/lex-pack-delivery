# delivery.lex — last-mile delivery pack (lex-ev-fleet#162).
#
# Sequences a day's parcel deliveries by calling lex-routing's VRP-with-time-
# windows solver (POST /vrp), and captures proof-of-delivery as tamper-evident
# evidence on the settlement trail. The delivery orders themselves live in lex-tms
# as service_kind='delivery' rows (#160); this pack plans over them and records
# the outcome.
#
#   POST /delivery/plan  { depot, stops:[{id,lat,lon,demand,ready,due,service}],
#                          capacity, max_vehicles, depot_ready, depot_due, profile }
#     -> proxies to lex-routing /vrp, records a `delivery.plan` trail event,
#        returns the routed plan { routes, unassigned }.
#   POST /delivery/pod   { order_id, outcome("delivered"|"failed"), note }
#     -> appends a signed `delivery.pod` event to the trail (provable delivery).

import "std.str" as str

import "std.time" as time

import "std.http" as http

import "std.bytes" as bytes

import "std.map" as map

import "lex-schema/json_value" as jv

import "lex-web/router" as router

import "lex-web/ctx" as ctx

import "lex-web/response" as resp

import "lex-trail/log" as tlog

import "lex-soft/src/settlement" as settlement

import "lex-soft/src/positions" as pos

fn jstr(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    Some(JStr(s)) => s,
    _ => "",
  }
}

# Plan the day's route by proxying the request to lex-routing's VRP solver, then
# stamp a `delivery.plan` event on the trail so the plan is auditable.
fn handle_plan(c :: ctx.Ctx, db :: Db, routing_url :: Str) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
  if str.is_empty(routing_url) {
    resp.json_status(503, "{\"error\":\"routing service not configured (ROUTING_URL unset)\"}")
  } else {
    let base := { method: "POST", url: str.concat(routing_url, "/vrp"), headers: map.new(), body: Some(bytes.from_str(c.body)), timeout_ms: Some(30000) }
    let req := http.with_header(base, "Content-Type", "application/json")
    match http.send(req) {
      Err(_) => resp.json_status(502, "{\"error\":\"routing service unreachable\"}"),
      Ok(res) => {
        let body_s := match bytes.to_str(res.body) {
          Ok(v) => v,
          Err(_) => "",
        }
        let tenant := ctx.header_or(c, "X-Tenant-Id", "demo")
        let log := settlement.trail_on(db)
        let payload := jv.stringify(JObj([("tenant", JStr(tenant)), ("planned_at_ms", JInt(time.now_ms()))]))
        let __e := tlog.append(log, "delivery.plan", None, payload)
        if res.status >= 400 {
          resp.json_status(502, str.concat("{\"error\":\"routing failed\",\"detail\":", str.concat(jv.stringify(JStr(body_s)), "}")))
        } else {
          resp.json(body_s)
        }
      },
    }
  }
}

# Record proof-of-delivery (or a failed attempt) as a tamper-evident trail event.
fn handle_pod(c :: ctx.Ctx, db :: Db) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
  match jv.parse(c.body) {
    Err(_) => resp.bad_request("{\"error\":\"invalid json\"}"),
    Ok(j) => {
      let order_id := jstr(j, "order_id")
      let outcome := jstr(j, "outcome")
      if str.is_empty(order_id) {
        resp.bad_request("{\"error\":\"order_id is required\"}")
      } else {
        if not (outcome == "delivered" or outcome == "failed") {
          resp.bad_request("{\"error\":\"outcome must be 'delivered' or 'failed'\"}")
        } else {
          let tenant := ctx.header_or(c, "X-Tenant-Id", "demo")
          let log := settlement.trail_on(db)
          let payload := jv.stringify(JObj([("order_id", JStr(order_id)), ("outcome", JStr(outcome)), ("note", JStr(jstr(j, "note"))), ("tenant", JStr(tenant)), ("at_ms", JInt(time.now_ms()))]))
          let __e := tlog.append(log, "delivery.pod", None, payload)
          resp.json_status(201, jv.stringify(JObj([("ok", JBool(true)), ("order_id", JStr(order_id)), ("outcome", JStr(outcome))])))
        }
      }
    },
  }
}

fn mount(r :: router.Router, db :: Db, routing_url :: Str) -> router.Router {
  let with_plan := router.route_effectful(r, "POST", "/delivery/plan", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
    handle_plan(c, db, routing_url)
  })
  router.route_effectful(with_plan, "POST", "/delivery/pod", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
    handle_pod(c, db)
  })
}

# The domain vocabulary this pack speaks (lex-soft/src/positions).
fn manifest() -> pos.PackManifest {
  { id: "delivery", title: "Last-mile delivery", tagline: "VRP-planned stops, closed out with tamper-evident proof of delivery.", pattern: "milestone_release", subject: "delivery", subject_ref_field: "order_id", custody_ref_field: "", parties: [{ position: "originator", name: "dispatcher", title: "Dispatcher — plans the day's stops via the VRP solver", field: "", required: false }, { position: "executor", name: "driver", title: "Driver — completes each stop and reports proof of delivery", field: "", required: false }, { position: "observer", name: "auditor", title: "Auditor — reads the plan/POD trail events", field: "", required: false }], relationships: [{ from: "dispatcher", to: "driver", role: "dispatch", label: "the dispatcher's plan assigns stops to the driver" }, { from: "driver", to: "auditor", role: "reporting", label: "proof of delivery is written for whoever audits the trail" }], event_kinds: ["delivery.plan", "delivery.pod"], evidence_kinds: ["proof_of_delivery"], settles: false, route_prefix: "/delivery" }
}

