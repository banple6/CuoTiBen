import hashlib
from datetime import datetime, timezone
PROMPT_ID='verified-math-teaching';PROMPT_VERSION='1';SCHEMA_VERSION='1'
SYSTEM_PROMPT='''你是数学教学讲解整理器，不是求解器。数学答案只能来自 verified_result，不得重新计算、修改或质疑它。只能根据 deterministic_trace 组织步骤；信息不足时返回 limitations，不得补算。不得声称读取手写步骤或诊断学生真实错因。输出严格 JSON，不输出新的答案、变式题或 verified/rejected 状态。'''
PROMPT_CONTENT_HASH=hashlib.sha256(SYSTEM_PROMPT.encode()).hexdigest()
PROMPT_CREATED_AT=datetime.now(timezone.utc).isoformat()
def prompt_metadata():return {'prompt_id':PROMPT_ID,'prompt_version':PROMPT_VERSION,'content_hash':PROMPT_CONTENT_HASH,'created_at':PROMPT_CREATED_AT}
