# DXCEL-BACKEND

합성 데이터 연구 대시보드의 DB·권한·API를 관리하는 저장소입니다.

## 개발 환경

- Node.js `26.3.1`, pnpm `10.34.9`
- 프로젝트 로컬 Supabase CLI `3.0.0`, Deno `2.9.6` (pnpm 의존성으로 고정)
- 로컬 DB/Edge Runtime 실행에는 Docker 호환 컨테이너 런타임이 필요합니다.

```bash
pnpm install --frozen-lockfile
cp .env.example .env.local
pnpm db:start
```

macOS에서는 Colima와 Docker CLI를 사용할 수 있습니다.

```bash
brew install colima docker
colima start --cpu 2 --memory 4 --disk 20
```

Colima 기동 후 `pnpm db:start`를 실행합니다. 최초 기동 시 이미지 다운로드가 필요합니다.
CLI와 Deno를 전역으로 설치할 필요는 없습니다. Deno 편집기 설정은 Edge Functions 경로에만 적용합니다.

개발을 마치면 `pnpm db:stop`으로 데이터를 보존하며 중지할 수 있습니다.
VM 자원까지 반환하려면 이어서 `colima stop`을 실행합니다. 다음 개발 때 Colima부터 다시 기동합니다.

로컬 Supabase 명령은 현재 Docker context의 로컬 socket을 사용하고, 공개 이미지용 임시 익명 설정을 적용합니다.
기존 Docker Desktop credential helper가 없는 환경에서도 전역 Docker 인증 설정을 변경하지 않습니다.
TCP/SSH 원격 Docker daemon은 이 개발 명령에서 거부합니다. private 이미지 인증용 명령은 아닙니다.

## 로컬 명령

| 명령                                 | 용도                                                                        |
| ------------------------------------ | --------------------------------------------------------------------------- |
| `pnpm check`                         | 저장소 포맷·Deno 검사·로컬 실행 도구 테스트                                 |
| `pnpm format`                        | 저장소 설정·문서 및 Deno 소스 포맷                                          |
| `pnpm db:start`                      | 로컬 Supabase 시작                                                          |
| `pnpm db:status`                     | 로컬 접속 정보 확인. 출력의 관리자 키를 공유하지 않습니다                   |
| `pnpm db:stop`                       | 로컬 Supabase 중지·데이터 보존                                              |
| `pnpm db:lint`                       | 실행 중인 로컬 DB의 SQL 검사                                                |
| `pnpm db:test`                       | 연구 스키마·권한·이력 pgTAP 테스트 실행                                     |
| `pnpm db:types`                      | 로컬 public 스키마의 TypeScript 타입을 `generated/database.types.ts`로 생성 |
| `pnpm functions:serve`               | 로컬 함수 추가 후 Edge Runtime 실행                                         |
| `pnpm supabase migration new <name>` | 새 migration 생성                                                           |

로컬 앱 API는 `http://127.0.0.1:54321`, Studio는 `http://127.0.0.1:54323`입니다.
인증 redirect는 프론트의 `http://127.0.0.1:3000/auth/callback`을 기준으로 합니다.
GitHub OAuth는 앱 등록·자격 증명이 필요한 후속 작업이며 현재 활성화하지 않습니다.

도메인 테이블·RLS·DB RPC는 `supabase/migrations/`에 구현되어 있습니다. 실행 중인 로컬 DB에는 `pnpm supabase migration up --local`로 미적용 migration을 추가 적용합니다. 기존 데이터를 초기화하지 않습니다.
`pnpm db:test`는 DB 권한·이력·집계 테스트를 실행합니다. `pnpm db:verify`는 로컬 PostgreSQL의 별도 임시 DB에서 migration 순차 적용과 동시성 검증을 실행하며 `psql`이 필요합니다. macOS에서는 `brew install libpq` 후 해당 bin 경로를 PATH에 추가할 수 있습니다.
Edge Function은 아직 없으므로 `functions:serve`는 후속 구현 이후 사용합니다. Deno lint의 소스 0개 결과를 기능 검증으로 해석하지 않습니다.
`pnpm db:types`는 실제 스키마의 타입을 생성하고 포맷합니다. 생성 실패 시 기존 파일을 보존합니다.
초기 seed는 비활성화했으며, synthetic 데이터가 필요해질 때 seed 파일과 설정을 함께 추가합니다.
원격 연결과 배포는 자동 실행하지 않습니다. 초기 스택은 analytics/vector/pooler 등 필요하지 않은 서비스를 비활성화해 자원을 줄입니다.

## 디렉터리

- `supabase/config.toml`: 로컬 스택과 인증 설정
- `supabase/functions/deno.json`: Edge Functions의 Deno 검사·포맷 설정
- `scripts/`: 로컬 Supabase 실행과 DB 타입 생성, 관련 테스트
- `docs/`: DB 설계와 구현 계약
- `supabase/migrations/`: 테이블·권한·RPC·결과 보존 migration
- `supabase/tests/database/`: pgTAP 회귀 테스트
- `generated/database.types.ts`: 실제 local public 스키마에서 생성한 타입

`contracts/`는 HTTP 수집 API를 구현할 때 추가합니다. 빈 디렉터리를 유지하기 위한 안내 파일은 두지 않습니다.

## 작업 규칙

- SQL·RLS·RPC 변경은 migration으로 관리합니다. 기존 migration을 덮어쓰지 않습니다.
- 원격 DB를 변경하는 명령은 로컬 개발 명령과 분리합니다. `db reset`은 초기 스크립트에 포함하지 않습니다.
- 커밋을 목적별로 나누고 변경 범위의 검사 결과를 남깁니다.
- 로컬 인증 정보와 실제 연구 데이터는 커밋하지 않습니다.
- 설정/README는 Prettier, Edge Functions는 Deno로 포맷합니다. 기존 설계 문서는 자동 포맷에서 제외합니다.
- CI는 정적 검사와 별도 DB job을 실행합니다. DB job은 로컬 스택에서 migration·SQL lint·pgTAP·migration 재적용/동시성·생성 타입 차이를 검사합니다.

## 초기 세팅 검증

- `pnpm install --frozen-lockfile`, 포맷·Deno 검사, 로컬 실행 도구 테스트 3건 통과
- Colima/Docker 및 로컬 Supabase 기동, PostgreSQL 17.11 접속 확인
- 인증 health·REST·Studio HTTP 200, 로컬 DB lint 오류 없음
- DB 타입 생성 명령 확인. 빈 스키마의 임시 생성 파일은 제거하고 도메인 migration 이후 생성합니다

위 목록은 초기 개발 기반 구축 당시의 검증 기록입니다. 현재 도메인·RLS 검증과 남은 API 범위는 [DB 구현 현황](docs/database-implementation.md)을 따릅니다.

## 설계 문서

- [DB·API 논리 설계](docs/database-design.md)
- [실제 DB 구현·RPC·검증 범위](docs/database-implementation.md)
- 전체 구조와 프론트엔드 설계는 `TEAM-DXCEL/DXCEL-FRONTEND`의 `docs/architecture.md`에서 관리합니다.

실제 DB 스키마·RLS·핵심 DB RPC까지 로컬에 구현했습니다. HTTP 수집 API·프론트 실제 조회 연결·외부 배포는 후속 구현 범위입니다.
