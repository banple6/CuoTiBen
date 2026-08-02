PROTOCOL_VERSION='1'
ALLOWED_SOLVER_IDS={'numeric_exact','linear_equation','quadratic_equation','linear_inequality'}
def validate_request(value):
    required={'protocol_version','solver_id','canonical_ast','problem_ir','analysis','constraints_snapshot','limits'}
    if not isinstance(value,dict) or set(value)!=required or value['protocol_version']!=PROTOCOL_VERSION or value['solver_id'] not in ALLOWED_SOLVER_IDS:raise ValueError('INVALID_WORKER_REQUEST')
def validate_response(value):
    required={'protocol_version','status','solver_id','solver_version','candidate_result','warnings','errors','timings'}
    if not isinstance(value,dict) or set(value)!=required or value['protocol_version']!=PROTOCOL_VERSION:raise ValueError('INVALID_WORKER_RESPONSE')
    if value['solver_id'] not in ALLOWED_SOLVER_IDS or value['status'] not in {'candidate','unsolved','unsupported','inconclusive','timeout','failed'}:raise ValueError('INVALID_WORKER_RESPONSE')
    if value.get('is_verified') or value.get('verification_status')=='verified':raise ValueError('WORKER_ATTEMPTED_VERIFIED')
