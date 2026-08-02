from dataclasses import dataclass
@dataclass(frozen=True)
class SolverExecutionLimits:
    total_timeout_ms:int=3000; build_timeout_ms:int=300; classification_timeout_ms:int=200; solve_timeout_ms:int=300; max_result_bytes:int=64_000; max_trace_entries:int=16
