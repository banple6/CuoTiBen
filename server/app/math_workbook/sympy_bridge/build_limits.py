from dataclasses import dataclass
@dataclass(frozen=True)
class SympyBuildLimits:
    max_nodes:int=500; max_depth:int=64; max_symbols:int=32; max_integer_digits:int=100; max_decimal_digits:int=100; max_power_abs_value:int=1000; max_relation_count:int=1; max_build_duration_ms:int=500
