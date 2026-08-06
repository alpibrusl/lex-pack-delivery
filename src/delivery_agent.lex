# delivery_agent.lex — an LLM-driven agent persona that operates THIS pack's
# own REST service (delivery.lex's /delivery/* routes).
#
# Same loopback-HTTP pattern as lex-pack-construction/src/construction_agent.lex.
# Only two routes exist: plan_route forwards straight through to /delivery/plan,
# which itself proxies to lex-routing's /vrp (the agent's tool calls this
# pack's own route, not lex-routing directly, so the plan.delivery trail
# event and the pack's own 502/503 error handling stay in the code path).

import "std.str" as str

import "std.http" as http

import "std.map" as map

import "std.bytes" as bytes

import "lex-schema/json_value" as jv

import "lex-schema/schema" as sch

import "lex-schema/error" as e

import "lex-spec/capability" as cap

import "lex-llm/src/tool" as t

import "lex-agent/src/server" as srv

import "lex-agent/src/agent_card" as card

import "lex-soft/src/runner" as runner

fn http_post_json(url :: Str, body :: Str, tenant :: Str) -> [net] jv.Json {
  let req0 := { method: "POST", url: url, headers: map.new(), body: Some(bytes.from_str(body)), timeout_ms: Some(30000) }
  let req1 := http.with_header(req0, "Content-Type", "application/json")
  let req := if str.is_empty(tenant) {
    req1
  } else {
    http.with_header(req1, "X-Tenant-Id", tenant)
  }
  match http.send(req) {
    Err(_) => JObj([("error", JStr("unreachable")), ("url", JStr(url))]),
    Ok(resp) => match bytes.to_str(resp.body) {
      Err(_) => JObj([("error", JStr("decode error"))]),
      Ok(b) => match jv.parse(b) {
        Err(_) => JStr(b),
        Ok(j) => j,
      },
    },
  }
}

# ── Capability ────────────────────────────────────────────────────────────────
fn delivery_capability() -> cap.Capability {
  cap.inbound("handle", "Operate last-mile delivery: plan a day's stops via the VRP solver and record proof of delivery.", { title: "DeliveryOps", description: "Inbound message for the delivery ops agent.", fields: [sch.required_str("text", [])] })
}

# ── Tools (self — this pack's own REST routes, no external backend) ──────────
fn stop_schema() -> sch.ModelSchema {
  { title: "Stop", description: "One delivery stop in a VRP plan.", fields: [sch.required_str("id", []), sch.required_float("lat", []), sch.required_float("lon", []), sch.optional(sch.required_float("demand", [])), sch.optional(sch.required_str("ready", [])), sch.optional(sch.required_str("due", [])), sch.optional(sch.required_float("service", []))] }
}

fn depot_schema() -> sch.ModelSchema {
  { title: "Depot", description: "The depot's coordinates, the plan's start/end point.", fields: [sch.required_float("lat", []), sch.required_float("lon", [])] }
}

fn make_delivery_tools(self_base_url :: Str) -> List[t.Tool] {
  [t.define("plan_route", "Plan a day's delivery stops via the VRP solver: pass the depot location and every stop (with its coordinates and any demand/time-window constraints), get back assigned routes per vehicle plus anything that couldn't be assigned.", { title: "PlanRoute", description: "VRP route planning, forwarded to the routing service.", fields: [sch.required_object("depot", depot_schema()), sch.required_array("stops", KObject(stop_schema()), []), sch.optional(sch.required_float("capacity", [])), sch.optional(sch.required_int("max_vehicles", [])), sch.optional(sch.required_str("depot_ready", [])), sch.optional(sch.required_str("depot_due", [])), sch.optional(sch.required_str("profile", []))] }, fn (args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
    Ok(http_post_json(str.concat(self_base_url, "/delivery/plan"), jv.stringify(args), ""))
  }), t.define("record_pod", "Record proof of delivery for an order: outcome must be 'delivered' or 'failed'. Use this to close out a stop once the driver reports back.", { title: "RecordPod", description: "Proof-of-delivery recording.", fields: [sch.required_str("order_id", []), sch.required_str("outcome", []), sch.optional(sch.required_str("note", []))] }, fn (args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
    Ok(http_post_json(str.concat(self_base_url, "/delivery/pod"), jv.stringify(args), ""))
  })]
}

# ── System prompt ──────────────────────────────────────────────────────────────
fn delivery_system_prompt(id :: Str) -> Str {
  str.join(["You are delivery ops agent ", id, ". You plan last-mile delivery routes and record proof of delivery.", " Use plan_route with the depot and every stop's coordinates (plus demand/time windows if given) to get an assigned route per vehicle. Once a driver reports back, use record_pod with the order_id and outcome ('delivered' or 'failed', with a note explaining any failure).", " Be precise about order_id and outcome, and always name which stops were left unassigned if the plan reports any."], "")
}

# ── Agent factory (the persona builder the pack mounts) ────────────────────────
fn make_delivery_def(db :: Db, id :: Str, base_url :: Str, self_base_url :: Str, provider_name :: Str, provider_url :: Str, provider_key :: Str, model_name :: Str) -> srv.AgentDef {
  let capability := delivery_capability()
  let cfg := { id: id, kind: "delivery-ops", system_prompt: delivery_system_prompt(id), model_name: model_name, provider_name: provider_name, provider_url: provider_url, provider_key: provider_key, backends: [{ key: "self_url", url: self_base_url }], intent_roles: [], tools: make_delivery_tools(self_base_url) }
  let handler := runner.make_handler(db, cfg)
  let c := card.make(id, str.concat("Delivery ops agent ", id), "0.1.0", base_url, [capability])
  srv.make_agent_def(c, [{ capability: capability, handle: handler }])
}

