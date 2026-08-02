from dataclasses import dataclass

@dataclass(frozen=True)
class ParseError(Exception):
    code: str
    position: int
    details: dict
    def as_dict(self): return {"code": self.code, "position": self.position, "details": self.details}
