from dataclasses import dataclass
@dataclass(frozen=True)
class SolverLimits:
    max_nodes:int=500; max_depth:int=64; max_symbols:int=1; max_polynomial_degree:int=2; max_integer_digits:int=100; max_coefficient_digits:int=100; max_candidate_count:int=4; max_solver_duration_ms:int=300; max_simplification_duration_ms:int=100
