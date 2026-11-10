# 평가 결과 자동 등록 v1

완료된 평가 한 건을 `POST /functions/v1/register-evaluation`으로 등록한다. 평가가 완료됐음을 확인하는 작업과 전송 재시도는 업로더가 담당한다.

## 인증과 범위

프로젝트 owner는 인증된 사용자 세션에서 `issue_ingestion_token(p_project, p_name, p_expires_at)`을 호출한다. 만료는 발급 시점부터 최대 90일이다. 응답의 `token`은 발급 시 한 번만 돌려주며, DB에는 SHA-256 해시만 저장한다. 업로더는 토큰을 `Authorization: Bearer <token>`으로 전송한다. `revoke_ingestion_token(p_project, p_token_id)`으로 폐기할 수 있다.

Edge Function은 프로젝트 범위와 토큰 발급자의 현재 쓰기 권한을 DB에서 검증한다. 업로더에는 Supabase 관리자 키가 필요 없다. 프로젝트의 로그인 세션은 토큰 발급과 실행 묶음 관리에 사용한다.

## 요청

`Content-Type: application/json`으로 64 KiB 이하의 본문을 전송한다. 아래 ID는 예시다. 실제 `groupId`와 `metric_id`는 사전에 구성한 실행 묶음과 해당 평가 조건에 속해야 한다. `repetition`과 `attempt`는 1부터 시작한다.

```json
{
  "schemaVersion": 1,
  "groupId": "00000000-0000-0000-0000-000000000041",
  "ingestionId": "exp143-adult-a-rep1-eval-v3-attempt1",
  "repetition": 1,
  "attempt": 1,
  "generationId": "exp143-adult-a-rep1-generation",
  "generationSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "previousRunId": null,
  "startedAt": "2026-11-10T00:00:00Z",
  "finishedAt": "2026-11-10T00:01:00Z",
  "metrics": [
    {
      "metric_id": "00000000-0000-0000-0000-000000000042",
      "state": "measured",
      "value": 0.5123
    }
  ]
}
```

- `ingestionId`는 평가 한 건의 등록 ID다. 재전송 시 본문과 함께 고정한다.
- `generationId`는 독립 생성 실행마다 고정한다. 같은 바이트를 생성한 독립 실행에도 각자의 ID를 부여한다. 재평가 시 생성 ID와 해시를 유지하고 등록 ID를 새로 만든다. 이전 등록이 확인됐으면 그 응답의 `runId`를 `previousRunId`에 넣는다.
- 평가 조건과 지표 정의는 `groupId`에서 확인한다. 등록은 실행을 저장하며, 실행 묶음 확정과 대표 결과 선정은 별도 작업이다.
- 지표 값은 유한한 원점수다. `missing`의 사유는 `not_applicable`, `not_computed`, `source_missing`이며 `error`의 사유는 `evaluation_failed`다. 두 상태에서는 `value` 없이 `reason`만 보낸다. 필드 허용 목록에 원본 파일, 모델, 진단, 경로는 포함하지 않는다.

## 응답과 재전송

| HTTP                  | 의미                                                          |
| --------------------- | ------------------------------------------------------------- |
| 201                   | 새 실행 등록. 응답은 `{"runId":"…","duplicate":false}`        |
| 200                   | 동일한 등록의 재전송. 기존 `runId`와 `duplicate:true` 반환    |
| 400 / 413 / 415 / 422 | 형식·크기·미디어 타입·평가 조건 오류. 요청을 확인한 뒤 수정   |
| 401                   | 만료·폐기·잘못된 토큰 또는 프로젝트 범위 오류                 |
| 409                   | 등록 ID·생성 ID 또는 실행 슬롯 충돌. 기존 등록을 확인         |
| 503                   | 일시적인 서버 오류. 동일 요청을 보관하고 지수 백오프로 재시도 |

HTTP 응답 없이 연결이 끊겨도 동일 본문과 ID를 사용해 재시도한다. 성공 응답을 받은 뒤에만 업로더에서 전송을 완료 처리한다.
