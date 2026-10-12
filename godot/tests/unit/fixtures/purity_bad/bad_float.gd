extends RefCounted
## Planted purity violations for tests/unit/test_core_purity.gd: the lint must flag this file.
## (English on purpose: it is a test fixture, never game code.)

var x: float = 1.5


func f() -> float:
	return sin(x)
