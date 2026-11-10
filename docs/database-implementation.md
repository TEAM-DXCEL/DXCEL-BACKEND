# DB 구현 현황

## 적용 범위

19개 도메인 테이블과 enum 6개, 프로젝트별 SELECT RLS, 권한을 검사하는 DB RPC 17개, 확정 결과 집계 view를 구현했다. SQL 파일이 DB 구조의 원본이다.

| Migration | 내용 |
| --- | --- |
| `20261105122000_research_tables.sql` | 테이블·타입·복합 FK·검사 제약·목록 인덱스 |
| `20261105122100_research_guards.sql` | RLS·직접 쓰기 제한·이력 보호·감사 trigger |
| `20261105122200_research_rpcs.sql` | 프로젝트·설계·결과 등록/확정·Baseline·노트 RPC와 집계 view |
| `20261105122300_result_history.sql` | 대표 결과 변경 참조 이력·누락 지표 결측 보존·확정된 평가 보호 |
| `20261105122400_audit_identifiers.sql` | 복합 대상의 감사 식별자와 작업별 감사 사유 분리 |
| `20261110160000_evaluation_ingestion.sql` | 등록 토큰 발급·폐기와 평가 자동 등록 권한 |
| `20261110180000_comparison_run_read.sql` | 등록된 실행의 비교 화면용 읽기 RPC |

UUID 식별자와 `timestamptz`를 사용한다. 실험 번호는 프로젝트 내 유일하다. 연구 테이블의 삭제 cascade는 사용하지 않는다. 결과·설계 버전·노트 버전·Baseline 버전·비교 조건·지표 정의는 추가 방식으로 보존하며, 수정·삭제 trigger로 보호한다.

## 접근 권한

- 비회원은 도메인 테이블 및 RPC에 접근할 수 없다.
- 구성원은 자신의 프로젝트만 조회한다. viewer는 쓰기를 할 수 없다.
- owner/editor의 변경은 프로젝트 권한을 확인하는 RPC로만 수행한다. 구성원 변경은 owner만 가능하며 마지막 owner 제거·강등은 거부한다.
- 클라이언트의 직접 INSERT/UPDATE/DELETE 권한은 없다. `service_role`에도 도메인 직접 쓰기 권한을 부여하지 않았다. `service_role`에는 Edge Function의 자동 등록 RPC와 비교 화면 서버의 읽기 RPC 실행을 허용한다.
- 등록 토큰 테이블은 owner에게도 해시를 제외한 메타데이터 열만 조회 허용한다. owner는 토큰을 발급·폐기할 수 있다. 자세한 요청·응답은 [자동 등록 계약](../contracts/evaluation-ingestion-v1.md)을 참고한다.
- 보조 함수는 비노출 `private` 스키마에 둔다. 모든 SECURITY DEFINER 함수의 search_path를 고정하고, 기본 실행 권한을 회수한 뒤 필요한 함수만 명시적으로 허용한다.

일반 변경은 프로젝트 행을 잠근 뒤 권한을 다시 확인한다. 같은 프로젝트의 쓰기는 직렬화되므로 소규모 협업의 정확성을 우선하며 쓰기 처리량이 필요해지면 잠금 범위를 재검토한다.

## DB RPC

| 함수 | 권한·역할 |
| --- | --- |
| `create_project` | 로그인 사용자, 프로젝트 생성과 최초 owner 추가를 한 transaction으로 처리 |
| `set_project_member` | owner, 구성원 추가·역할 변경·제거 (`p_role = null`) |
| `create_experiment` | owner/editor, 실험과 설계 v1 생성 |
| `revise_experiment` | owner/editor, expected_revision 일치 시 새 설계 버전 추가 |
| `define_metric` | owner/editor, 단위·개선 방향을 포함한 지표 정의 버전 생성 |
| `create_comparison_context` | owner/editor, 데이터셋·분할·평가 버전·평가량·지표 집합을 고정 |
| `create_run_group` | owner/editor, 특정 설계·조건·설정의 반복 묶음 생성 |
| `record_run` | owner/editor, 종료된 실행과 지표를 원자적으로 등록 |
| `finalize_run_group` | owner/editor, 포함·제외 목록 검증 후 확정 |
| `set_representative_result` | owner/editor, 확정 결과 선정과 교체 이유 보존 |
| `create_baseline_version` | owner/editor, 내부 확정 결과 또는 출처가 있는 보고값을 새 버전으로 저장 |
| `create_note`, `revise_note` | owner/editor, 노트 생성과 expected_revision에 따른 새 본문 버전 추가 |

정확한 인자 이름·반환 타입은 `generated/database.types.ts`의 `Functions`를 따른다. 실험·노트의 충돌은 SQLSTATE `40001`, 다른 내용으로 같은 등록 ID를 재사용하면 `23505`, 프로젝트 접근 거부는 `42501`로 구분한다. HTTP 응답 코드 변환은 향후 API 계층의 책임이다.

`record_run`은 완료 결과 수집용이므로 `succeeded`, `failed`, `cancelled`만 받는다. enum의 `queued`, `running`은 이후 실행 상태 수집 계약을 위한 값이며 현재 상태 전이 RPC는 없다. 성공 결과는 생성물 fingerprint가 필요하다. 재평가는 이전 실행을 참조하는 새 ID로 추가한다.

지표 입력은 `[{metric_id, state, value?, reason?}]` 형태다. context의 지표 정의 UUID가 버전·단위를 고정한다. 측정값은 유한 수치만 허용한다. 결측·오류는 값 없이 사유가 있어야 한다. 등록 요청에서 빠진 context 지표는 `missing / Not supplied in registration`으로 저장한다. 지표 순서를 정규화한 요청을 비교하여 같은 등록 ID·같은 내용은 같은 실행 ID를 반환하며, 서로 다른 내용은 충돌한다. 등록 실패 시 생성물·실행·지표가 모두 rollback된다.

## 확정과 집계

확정하려면 모든 예상 반복 번호가 중복 없이 선택 또는 제외로 설명되어야 하고, 선택이 최소 하나 있어야 한다. 선택된 실행은 성공 상태이고 같은 설계 버전·비교 조건·설정을 사용해야 한다. 필수 지표는 모두 측정되어야 한다. 동일 생성물 fingerprint를 가진 복수 평가를 독립 반복으로 중복 집계하지 않는다.

부분 재평가는 같은 설계·조건·설정의 새 묶음에서 이전 실행을 참조해 확정한다. 확정된 묶음·포함/제외·결과 지표는 변경하지 않는다. 대표 결과 교체 시 감사 이력에 이전/새 실행 묶음과 비교 조건 UUID, 이유, 작성자·시각을 남긴다.

`run_group_metric_summaries`는 확정 selection 기준 평균·표본 표준편차·측정 표본 수·결측/오류 수를 제공한다. 표본이 하나면 표준편차는 null이다. security_invoker view로 기초 테이블의 RLS를 유지한다. 서로 다른 조건 간 delta·순위·paired 분석·상대 개선율은 계산하지 않는다. 조건 미확인 보고값은 context_id가 null인 참고 기록으로 남긴다.

## 로컬 검증과 CI

```bash
pnpm db:start
pnpm supabase migration up --local
pnpm db:lint
pnpm db:test
pnpm db:verify
pnpm db:types
pnpm check
```

- pgTAP: RLS·역할 승격·마지막 owner·프로젝트 간 FK·유한 수치·등록 멱등성/충돌·원자성·확정 불변성·지표 결측·비교 조건·같은 생성물 중복·노트 충돌·Baseline/대표 결과 이력·집계 검증. 테스트 기록은 transaction rollback으로 제거한다.
- `db:verify`: loopback의 로컬 DB 포트 54322에만 접속하며 별도의 무작위 이름 임시 DB에서 migration 7개를 처음부터 적용한다. Supabase와 같은 역할이 존재하는 로컬 클러스터에서 최소 `auth.users`·`auth.uid()` fixture를 사용하므로 실제 Auth 전체를 재현하는 검증은 아니다. 실제 Auth 스키마와의 호환성은 실행 중인 Supabase의 pgTAP 테스트가 별도로 검증한다.
- 임시 DB에서는 같은 등록의 동시 요청, 설계·노트 동시 편집, 두 owner의 동시 강등도 독립 연결로 검증한다. 실패하더라도 finally에서 해당 임시 DB만 삭제한다. 기존 로컬 데이터는 reset하지 않는다.
- CI는 새 Supabase 스택에서 migration을 적용하고 SQL lint·pgTAP·재적용/동시성·생성 타입 차이를 검사한다.

## 남은 연결 작업

프론트 개발 서버는 비공개 Supabase Storage에서 기존 기록을 읽고, 읽기 RPC로 지정된 등록 실행을 조회한다. 프로젝트별 실행 목록 조회, 로그인 연결, 업로더 자동 실행, 실행 상태 전이, 보관 상태 변경 UI 및 백업·복원 운영 절차는 별도 작업이다.

참고한 공식 문서: [Supabase 함수 권한](https://supabase.com/docs/guides/database/functions), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Postgres row security와 FK](https://www.postgresql.org/docs/current/ddl-rowsecurity.html).
