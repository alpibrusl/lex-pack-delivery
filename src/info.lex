# info.lex — the delivery agent-domain manifest (pack.PackInfo).
#
# The DomainPack counterpart of this pack's REST pos.PackManifest: how a
# console should PRESENT the delivery-ops persona — label, tagline, starter
# prompts. Served by the host under /platform/packs's agent_packs field.

import "lex-soft/src/pack" as pack

fn info() -> pack.PackInfo {
  { name: "delivery", title: "Delivery", tagline: "VRP-planned last-mile stops, closed out with tamper-evident proof of delivery.", personas: [{ kind: "delivery-ops", title: "Delivery ops", tagline: "Plans routes via the VRP solver and records proof of delivery.", suggested_prompts: ["Plan a route from the depot at 52.37,4.90 to stops S1 (52.38,4.91) and S2 (52.36,4.89).", "Record proof of delivery for order O-100: delivered.", "Record a failed delivery for order O-101: no one home."] }] }
}

