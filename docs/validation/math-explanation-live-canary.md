# Math explanation live canary

- Status: `not_executed`
- Execution date: `2026-08-04`
- Commit: `6f38aaceb82943fb6debf12dddbca47df9e701c2`
- Branch: `agent/math-explanation-live-canary`
- Provider: `deepseek`
- Configured model: `deepseek-chat`
- Actual model: `None`
- Prompt: `verified-math-teaching` v`2` (`c65833c81914b52ee30b5e7d65e570656a5ecaf1d95a48ff709588de7a43764f`)
- Prompt created at: `2026-08-02T00:00:00Z`
- Schema/trace/renderer: `2`/`1`/`1`

Reason: `API key not configured`

## Seven fixed samples

| Sample | Formula | Status | Logical requests | Network attempts | Retries | Provider id | Persisted | Readback |
|---|---|---|---:|---:|---:|---|---|---|
| `linear_unique` | `2x+3=7` | `not_executed` | 0 | 0 | 0 | `none` / False | False | False |
| `linear_no_solution` | `0x=1` | `not_executed` | 0 | 0 | 0 | `none` / False | False | False |
| `linear_identity` | `0x=0` | `not_executed` | 0 | 0 | 0 | `none` / False | False | False |
| `quadratic_two_roots` | `x^2-5x+6=0` | `not_executed` | 0 | 0 | 0 | `none` / False | False | False |
| `quadratic_repeated_root` | `x^2-2x+1=0` | `not_executed` | 0 | 0 | 0 | `none` / False | False | False |
| `quadratic_no_real_root` | `x^2+1=0` | `not_executed` | 0 | 0 | 0 | `none` / False | False | False |
| `linear_inequality_negative` | `-2x<4` | `not_executed` | 0 | 0 | 0 | `none` / False | False | False |

## Totals

```json
{
  "cached_tokens": null,
  "duration_ms": null,
  "estimated_cost": null,
  "failed_samples": 0,
  "input_tokens": null,
  "logical_requests": 0,
  "network_attempts": 0,
  "not_executed_samples": 7,
  "output_tokens": null,
  "retries": 0,
  "sample_count": 7,
  "validated_samples": 0
}
```

The JSON artifact contains only redacted metrics and checklist statuses; it never contains an API key, Authorization header, raw model response, full explanation input, absolute path, or user data.
