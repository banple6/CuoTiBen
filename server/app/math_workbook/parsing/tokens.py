from dataclasses import dataclass
from enum import StrEnum

class TokenType(StrEnum):
    INTEGER='INTEGER'; DECIMAL='DECIMAL'; SYMBOL='SYMBOL'; PLUS='PLUS'; MINUS='MINUS'; MULTIPLY='MULTIPLY'; DIVIDE='DIVIDE'; POWER='POWER'; FRAC='FRAC'; SQRT='SQRT'; LEFT_PAREN='LEFT_PAREN'; RIGHT_PAREN='RIGHT_PAREN'; LEFT_BRACKET='LEFT_BRACKET'; RIGHT_BRACKET='RIGHT_BRACKET'; LEFT_BRACE='LEFT_BRACE'; RIGHT_BRACE='RIGHT_BRACE'; EQUAL='EQUAL'; LESS_THAN='LESS_THAN'; LESS_THAN_OR_EQUAL='LESS_THAN_OR_EQUAL'; GREATER_THAN='GREATER_THAN'; GREATER_THAN_OR_EQUAL='GREATER_THAN_OR_EQUAL'; COMMA='COMMA'; EOF='EOF'

@dataclass(frozen=True)
class Token:
    type: TokenType; lexeme: str; normalized_value: str; start: int; end: int; source_formula_id: str; source_span: dict
    def to_dict(self): return {'type':self.type.value,'lexeme':self.lexeme,'normalized_value':self.normalized_value,'start':self.start,'end':self.end,'source_formula_id':self.source_formula_id,'source_span':self.source_span}
