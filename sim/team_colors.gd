extends RefCounted
## Customizable team palette. Colors are static vars so a future settings/Config
## screen can override them at runtime; the blend outline is derived from the two
## team outline colors so it stays consistent (blue + red = purple). Indices:
## 0 = Neutral, 1 = Team 1, 2 = Team 2.

static var fill := [Color(0.5, 0.52, 0.55), Color(0.24, 0.34, 0.62), Color(0.6, 0.3, 0.27)]
static var outline := [Color(0.72, 0.74, 0.77), Color(0.3, 0.55, 1.0), Color(0.96, 0.33, 0.28)]

static func fill_color(owner: int) -> Color:
	return fill[owner]

## Outline color for a frontier category: 0 neutral, 1 team1, 2 team2, 3 blend.
static func outline_color(category: int) -> Color:
	if category == 3:
		return outline[1].lerp(outline[2], 0.5)
	return outline[category]
