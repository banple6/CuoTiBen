from dataclasses import dataclass
ANALYSIS_VERSION='1'
@dataclass(frozen=True)
class AnalysisReport:
    problem_id:str;parse_result_id:str;build_result_id:str;status:str;structural_features:dict;classification:dict;domain_constraints:tuple[dict,...];warnings:tuple[str,...];unsupported_features:tuple[str,...]
    def to_dict(self):return {'analysis_version':ANALYSIS_VERSION,**self.__dict__}
