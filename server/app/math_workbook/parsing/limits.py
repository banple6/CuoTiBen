from dataclasses import dataclass

@dataclass(frozen=True)
class ParserLimits:
    max_input_chars: int = 4000
    max_tokens: int = 1000
    max_ast_nodes: int = 500
    max_ast_depth: int = 64
    max_integer_digits: int = 100
    max_decimal_digits: int = 100
    max_power_abs_value: int = 1000
    max_symbols: int = 32
    max_relations: int = 1
