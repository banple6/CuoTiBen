from dataclasses import dataclass
@dataclass(frozen=True)
class SolverError(Exception):
    code:str; details:dict
    def as_dict(self):return {'code':self.code,'details':self.details}
