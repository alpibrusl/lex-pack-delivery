# tests/test_delivery.lex — manifest coverage for src/delivery.lex.
#
# The effectful routes (plan proxies lex-routing, pod appends a trail event)
# need a live routing backend + DB to exercise meaningfully — that's covered
# by lex-ev-fleet's own integration testing of the mounted deployment.

import "std.list" as list

import "lex-soft/src/positions" as pos

import "../src/delivery" as delivery

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

fn test_manifest_is_valid() -> Result[Unit, Str] {
  let m := delivery.manifest()
  assert_true(list.is_empty(pos.validate(m)), "delivery's own manifest must satisfy the shared position/pattern validator")
}

fn test_manifest_route_prefix() -> Result[Unit, Str] {
  assert_true(delivery.manifest().route_prefix == "/delivery", "manifest route_prefix must match the mounted routes")
}

fn test_manifest_does_not_settle() -> Result[Unit, Str] {
  assert_true(not delivery.manifest().settles, "proof of delivery is evidence, not a settlement — the manifest must not advertise a settler")
}

fn run_all() -> List[Result[Unit, Str]] {
  [test_manifest_is_valid(), test_manifest_route_prefix(), test_manifest_does_not_settle()]
}

