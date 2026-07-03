extends RefCounted
class_name Inventory

# Minimal flat-counter economy — matches the codebase's existing loose-float
# style (NPC.wealth/food) rather than a full item/stack system. Real
# harvesting/economy stays deferred; starts from a flat stockpile so
# BuildMode's resource costs mean something today. Also the natural seed for
# a future equipped-items list (see PlayerStats.equipment_bonus) — not built
# this pass, but the shape shouldn't fight that later.

var counts: Dictionary = {"wood": 20.0, "stone": 10.0}

func has(resource: String, amount: float) -> bool:
	return counts.get(resource, 0.0) >= amount

func can_afford(costs: Dictionary) -> bool:
	for resource in costs:
		if not has(resource, costs[resource]):
			return false
	return true

func spend(costs: Dictionary) -> bool:
	if not can_afford(costs):
		return false
	for resource in costs:
		counts[resource] -= costs[resource]
	return true

func add(resource: String, amount: float) -> void:
	counts[resource] = counts.get(resource, 0.0) + amount
