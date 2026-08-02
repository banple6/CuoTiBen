from .errors import ParseError
from .limits import ParserLimits
from .tokens import Token,TokenType

_SINGLE={'+':TokenType.PLUS,'-':TokenType.MINUS,'*':TokenType.MULTIPLY,'/':TokenType.DIVIDE,'^':TokenType.POWER,'(':TokenType.LEFT_PAREN,')':TokenType.RIGHT_PAREN,'[':TokenType.LEFT_BRACKET,']':TokenType.RIGHT_BRACKET,'{':TokenType.LEFT_BRACE,'}':TokenType.RIGHT_BRACE,'=':TokenType.EQUAL,'<':TokenType.LESS_THAN,'>':TokenType.GREATER_THAN,',':TokenType.COMMA}
_FORBIDDEN=set("'\"`;:.\\_")
def tokenize(text:str,source_formula_id:str,limits:ParserLimits=ParserLimits())->list[Token]:
    if len(text)>limits.max_input_chars: raise ParseError('INPUT_LENGTH_LIMIT_EXCEEDED',limits.max_input_chars,{'limit':limits.max_input_chars})
    out=[];i=0
    while i<len(text):
        c=text[i]
        if c.isspace():i+=1;continue
        if c in _FORBIDDEN:
            # Backslash is permitted only for strictly whitelisted commands.
            if c=='\\':
                if text.startswith('\\frac',i): out.append(Token(TokenType.FRAC,'\\frac','\\frac',i,i+5,source_formula_id,{'start':i,'end':i+5}));i+=5;continue
                if text.startswith('\\sqrt',i): out.append(Token(TokenType.SQRT,'\\sqrt','\\sqrt',i,i+5,source_formula_id,{'start':i,'end':i+5}));i+=5;continue
                raise ParseError('UNSUPPORTED_LATEX_COMMAND',i,{'input':text[i:i+32]})
            raise ParseError('FORBIDDEN_CHARACTER',i,{'character':c})
        if text.startswith('<=',i): typ,size=TokenType.LESS_THAN_OR_EQUAL,2
        elif text.startswith('>=',i): typ,size=TokenType.GREATER_THAN_OR_EQUAL,2
        elif c in _SINGLE: typ,size=_SINGLE[c],1
        else: typ=None;size=0
        if typ:
            out.append(Token(typ,text[i:i+size],text[i:i+size],i,i+size,source_formula_id,{'start':i,'end':i+size}));i+=size;continue
        if c.isdigit():
            j=i
            while j<len(text) and text[j].isdigit():j+=1
            decimal=False
            if j<len(text) and text[j]=='.':
                decimal=True;j+=1;k=j
                while j<len(text) and text[j].isdigit():j+=1
                if k==j:raise ParseError('INVALID_DECIMAL',i,{})
            digits=text[i:j].replace('.',''); limit=limits.max_decimal_digits if decimal else limits.max_integer_digits
            if len(digits)>limit:raise ParseError('NUMBER_DIGIT_LIMIT_EXCEEDED',i,{'limit':limit})
            out.append(Token(TokenType.DECIMAL if decimal else TokenType.INTEGER,text[i:j],text[i:j],i,j,source_formula_id,{'start':i,'end':j}));i=j;continue
        if c.isascii() and c.isalpha():
            # a single letter only; words/functions are intentionally not a language feature.
            if i+1<len(text) and text[i+1].isascii() and text[i+1].isalpha():raise ParseError('UNSUPPORTED_IDENTIFIER',i,{'input':text[i:i+32]})
            out.append(Token(TokenType.SYMBOL,c,c,i,i+1,source_formula_id,{'start':i,'end':i+1}));i+=1;continue
        raise ParseError('UNSUPPORTED_TOKEN',i,{'character':c})
    if len(out)>limits.max_tokens:raise ParseError('TOKEN_LIMIT_EXCEEDED',len(text),{'limit':limits.max_tokens})
    out.append(Token(TokenType.EOF,'','',len(text),len(text),source_formula_id,{'start':len(text),'end':len(text)}));return out
