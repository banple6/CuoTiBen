import re
import sympy
from .build_errors import BuildError

_NAME=re.compile(r'^[A-Za-z]$')
DOMAIN_BUILDERS={'real':lambda name:sympy.Symbol(name,real=True),'integer':lambda name:sympy.Symbol(name,integer=True),'positive_real':lambda name:sympy.Symbol(name,real=True,positive=True),'nonnegative_real':lambda name:sympy.Symbol(name,real=True,nonnegative=True)}
class SymbolTable:
    def __init__(self,variables:list[dict]):
        self.metadata={};self.symbols={}
        for item in variables:
            name=item.get('name');domain=item.get('domain')
            if not isinstance(name,str) or not _NAME.fullmatch(name):raise BuildError('INVALID_SYMBOL_NAME',{'name':name})
            if domain not in DOMAIN_BUILDERS:raise BuildError('UNKNOWN_SYMBOL_DOMAIN',{'domain':domain})
            self.symbols[name]=DOMAIN_BUILDERS[domain](name);self.metadata[name]={'domain':domain,'domain_source':item.get('domain_source','system_default')}
    def get(self,name):
        if name not in self.symbols:raise BuildError('SYMBOL_NOT_IN_PROBLEM_IR',{'name':name})
        return self.symbols[name]
