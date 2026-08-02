from dataclasses import dataclass

NORMALIZATION_VERSION='v1'
@dataclass(frozen=True)
class NormalizedInput:
    original: str; normalized: str; transformations: tuple[str,...]; position_map: tuple[int,...]
    def to_dict(self): return {'original':self.original,'normalized':self.normalized,'normalization_version':NORMALIZATION_VERSION,'transformations':list(self.transformations),'position_map':list(self.position_map)}

_REPLACEMENTS=(('−','-','unicode_minus'),('﹣','-','small_minus'),('×','*','unicode_multiply'),('÷','/','unicode_divide'),('≤','<=','unicode_less_equal'),('≥','>=','unicode_greater_equal'),('（','(','fullwidth_left_paren'),('）',')','fullwidth_right_paren'),('\\times','*','latex_times'),('\\cdot','*','latex_cdot'),('\\leq','<=','latex_leq'),('\\le','<=','latex_le'),('\\geq','>=','latex_geq'),('\\ge','>=','latex_ge'))
def normalize(source:str)->NormalizedInput:
    output=source; transformations=[]
    for old,new,name in _REPLACEMENTS:
        if old in output: output=output.replace(old,new);transformations.append(name)
    compact=' '.join(output.split())
    if compact != output: transformations.append('whitespace')
    # Mapping is conservative: output positions point into original if unchanged; transformed spans use first source occurrence.
    mapping=tuple(min(i,len(source)) for i in range(len(compact)+1))
    return NormalizedInput(source,compact,tuple(transformations),mapping)
