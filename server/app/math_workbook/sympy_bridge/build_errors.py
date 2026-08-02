from dataclasses import dataclass
@dataclass(frozen=True)
class BuildError(Exception):
    code:str; details:dict
    def as_dict(self):return {'code':self.code,'details':self.details}
