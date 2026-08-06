# tests/test_delivery_agent.lex — pure-logic coverage for src/delivery_agent.lex.
#
# lex test discards run_all's return value and only checks whether the call
# raises a runtime error -- see lex-ag-ui's README for the full writeup.
# This file forces a real runtime error when count_failures(...) > 0 so
# lex test/lex ci are real gates here.

import "std.list" as list

import "lex-schema/json_value" as jv

import "lex-schema/schema" as sch

import "lex-llm/src/tool" as t

import "../src/delivery_agent" as agent

fn pass() -> Result[Unit, Str] {
  Ok(())
}

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    pass()
  } else {
    Err(label)
  }
}

fn schema_of(name :: Str) -> Option[sch.ModelSchema] {
  match t.find_by_name(agent.make_delivery_tools("http://127.0.0.1:8100"), name) {
    None => None,
    Some(tool) => Some(tool.params),
  }
}

fn test_two_tools_defined() -> Result[Unit, Str] {
  assert_true(list.len(agent.make_delivery_tools("http://127.0.0.1:8100")) == 2, "delivery has exactly 2 REST routes today, so exactly 2 tools should be defined")
}

fn test_plan_route_schema_accepts_documented_shape() -> Result[Unit, Str] {
  let stop := JObj([("id", JStr("S1")), ("lat", JFloat(52.38)), ("lon", JFloat(4.91))])
  let sample := JObj([("depot", JObj([("lat", JFloat(52.37)), ("lon", JFloat(4.9))])), ("stops", JList([stop]))])
  match schema_of("plan_route") {
    None => Err("plan_route tool must be defined"),
    Some(schema) => match sch.validate(schema, sample) {
      Err(_) => Err("plan_route's schema must accept a depot + stops list matching delivery.lex's documented POST /delivery/plan body"),
      Ok(_) => pass(),
    },
  }
}

fn test_record_pod_schema_accepts_documented_shape() -> Result[Unit, Str] {
  let sample := JObj([("order_id", JStr("O-100")), ("outcome", JStr("delivered"))])
  match schema_of("record_pod") {
    None => Err("record_pod tool must be defined"),
    Some(schema) => match sch.validate(schema, sample) {
      Err(_) => Err("record_pod's schema must accept delivery.lex's documented POST /delivery/pod body"),
      Ok(_) => pass(),
    },
  }
}

fn test_record_pod_schema_requires_outcome() -> Result[Unit, Str] {
  let bad := JObj([("order_id", JStr("O-100"))])
  match schema_of("record_pod") {
    None => Err("record_pod tool must be defined"),
    Some(schema) => match sch.validate(schema, bad) {
      Err(_) => pass(),
      Ok(_) => Err("record_pod's schema must require outcome"),
    },
  }
}

fn suite_pure() -> List[Result[Unit, Str]] {
  [test_two_tools_defined(), test_plan_route_schema_accepts_documented_shape(), test_record_pod_schema_accepts_documented_shape(), test_record_pod_schema_requires_outcome()]
}

fn count_failures(results :: List[Result[Unit, Str]]) -> Int {
  list.fold(results, 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

fn run_all() -> Int {
  let failures := count_failures(suite_pure())
  let _crash_if_failed := if failures > 0 {
    1 / 0
  } else {
    0
  }
  failures
}

