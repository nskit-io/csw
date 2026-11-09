# CSW (Claude Subscription Worker)

**내 Claude CLI(`claude -p`)를 로컬 REST API로 감싸는 개인 개발자 도구.**

[🇬🇧 English](./README.md) · [🇯🇵 日本語](./README.ja.md) · [🇨🇳 中文](./README.zh.md)

[아키텍처](./architecture/overview.md) | [Worker 모드](./architecture/worker-mode.md) | [API 스펙](./reference/api-spec.md) | [스키마](./reference/schema.sql)

> [**NSKit**](https://github.com/nskit-io/nskit-io) 프로젝트의 개발자 도구 — *갇혀 있어서 무한 조합*. CSW는 개인·개발용 도구입니다. 내가 로그인한 Claude CLI를 내 스크립트와 로컬 도구가 내 기기(또는 사설망)의 REST API로 호출할 수 있게 합니다. 상용·프로덕션 서비스의 백엔드가 아닙니다.

---

## 문제

Claude API는 **토큰 단위 과금**입니다. 요청마다 입력·출력 토큰이 계량되므로, 처리량이 늘어나는 만큼 청구액도 함께 늘어납니다.

Claude 구독은 **월 정액**이며, 플랜의 사용 한도 안에서 CLI(`claude -p`)로 쓸 수 있습니다.

**CSW는 이 CLI를 내 용도로 감쌉니다.** Claude CLI를 REST API 서버 뒤에 두어, 개인 스크립트·로컬 도구·개발 실험이 세션·프리셋·캐싱과 함께 호출할 수 있게 합니다.

> **사용 범위.** Claude 구독은 구독자 본인의 사용을 위한 것이며 Anthropic의 이용 정책과 플랜 한도를 따릅니다. CSW는 본인의 개인·개발 작업에만 쓰십시오. 다른 사용자에게 제공하는 제품·서비스, 상용·프로덕션 워크로드에는 [Claude API](https://www.anthropic.com/api)를 쓰십시오. 최신 API 가격과 플랜 정보: [anthropic.com/pricing](https://www.anthropic.com/pricing).

## 무엇을 쓸까

| | Claude API | CSW를 통한 내 구독 |
|---|---|---|
| 과금 | 토큰 단위 | 본인의 월 정액 플랜 |
| 처리량 | 병렬, API 요금 등급의 rate limit | 플랜 한도와 워커 세션 수에 제한 |
| 용도 | 다른 사용자에게 제공하는 제품·서비스, 상용·프로덕션 워크로드 | 본인의 개인·개발 작업: 스크립트, 로컬 도구, 실험 |

응답 캐싱을 켜면 캐시 적중 시 Claude를 아예 호출하지 않으므로, 반복되는 로컬 호출이 빠르고 플랜 한도 안에 머뭅니다.

## 아키텍처

CSW는 두 가지 모드로 동작합니다:

### Standard 모드

상태 없는(stateless) 처리. 요청마다 새 `claude -p` 프로세스를 생성하고 실행 후 반환합니다.

- **장점**: 단순, 안정적, 상태 관리 불필요
- **단점**: Cold-start 오버헤드 (요청당 ~14-40초), 대화 컨텍스트 없음
- **적합**: 단건 처리, 배치 작업

### Worker 모드 (v2)

tmux 기반 영속 세션. Claude가 tmux 세션에서 상시 실행되며, 파일 기반 inbox/outbox로 명령을 전달받습니다.

- **장점**: 요청당 더 빠름 (요청마다 ~14-40초의 cold-start 없음), 대화 컨텍스트 유지, `alwaysOn` 지원
- **단점**: 더 복잡한 생명주기 관리, 초기 세션 생성 ~16초
- **적합**: 대화형 로컬 도구, 대화형 워크플로우, 잦은 요청

자세한 내용은 [Worker 모드 아키텍처](./architecture/worker-mode.md) 참조.

## 핵심 기능

| 기능 | 설명 |
|------|------|
| **세션 관리** | MySQL 기반 대화 생성/재개, 메시지 히스토리 자동 추적 |
| **응답 캐싱** | Simple(1:1) + Pool([Growing Pool Cache](https://github.com/nskit-io/growing-pool-cache)) |
| **프리셋 시스템** | 재사용 가능한 프롬프트 템플릿, 변수 치환 |
| **프롬프트 조립** | 시스템 프롬프트 + 메모리 + 히스토리 자동 조합 |
| **응답 파싱** | text/JSON/structured output + JSON 스키마 검증 |
| **히스토리 압축** | 메시지 임계치 초과 시 지정된 범용 워커가 자동 요약 |
| **Replica·대기열** | 워커 하나가 replica(병렬 tmux 세션) 여러 개를 운영, 모두 바쁘면 기본 최대 60초 대기 |
| **Worker 헬스** | 30초 주기 체크, 행 감지 시 자동 재시작, 서버 재부팅 시 복원 |

## API 개요

| 메서드 | 엔드포인트 | 설명 |
|--------|----------|------|
| `POST` | `/api/v1/process` | AI 요청 처리 (stateless/새 세션/기존 세션) |
| `GET` | `/api/v1/sessions` | 세션 목록 |
| `GET` | `/api/v1/sessions/:id` | 세션과 메시지 조회 |
| `POST` | `/api/v1/sessions/:id/archive` | 세션 보관 |
| `GET/POST` | `/api/v1/sessions/:id/memory` | 세션 메모리 조회/설정 |
| `GET/POST` | `/api/v1/presets` | 프리셋 목록/생성 |
| `GET/PUT/DELETE` | `/api/v1/presets/:id` | 프리셋 CRUD (관리) |
| `POST` | `/api/v1/presets/:id/run` | 프리셋을 `/process` 요청 본문으로 풀어서 반환 |
| `POST` | `/api/v1/presets/:id/generate-sample` | 프리셋 샘플 입력 재생성 (관리) |
| `GET` | `/api/v1/jobs` | 최근 작업 목록 |
| `GET` | `/api/v1/jobs/:id` | 작업 조회 |
| `GET` | `/api/v1/cache/stats` | 캐시 통계 |
| `GET/DELETE` | `/api/v1/cache/:key` | 캐시 항목 조회/삭제 (삭제 = 관리) |
| `POST` | `/api/v1/cache/purge` | 만료 캐시 정리 (관리) |
| `POST` | `/api/v1/workers` | Worker 생성 (관리) |
| `GET` | `/api/v1/workers` | Worker 목록 |
| `GET` | `/api/v1/workers/:name` | Worker 상태 조회 |
| `POST` | `/api/v1/workers/:name/wake` | 유휴 Worker 깨우기 |
| `POST` | `/api/v1/workers/:name/scale` | Worker replica 수 설정 (관리) |
| `POST` | `/api/v1/workers/:name/restart` | Worker 재시작 (관리) |
| `DELETE` | `/api/v1/workers/:name` | Worker 삭제 (관리) |

"관리" 엔드포인트는 서버 상태를 바꿉니다(워커는 호스트에서 프로세스를 실행합니다). API 전체를 내부망에 두세요 — [보안](#보안) 참조.

전체 스펙은 [API Specification](./reference/api-spec.md) 참조.

## 보안

CSW는 호스트에서 CLI와 tmux 세션을 구동하므로, API를 관리 표면으로 취급해야 합니다.

- **공개 인터넷에 노출하지 않습니다.** 내부망에서 운영하고, 앞단에 인증 프록시나 IP 허용 목록을 둡니다. 레퍼런스 서버에는 자체 인증이 없습니다.
- **호스트에 닿는 모든 식별자를 검증합니다.** 워커 이름은 허용 문자 패턴(`^[a-z0-9][a-z0-9-]{0,31}$`)과 일치해야 하며, 그 외 값은 `400`으로 거부합니다.
- **셸 문자열이 아니라 argv로 실행합니다.** `tmux` 등 외부 명령에는 값을 별도 인자(`execFile` 방식)로 넘기고, 명령 문자열에 끼워 넣지 않습니다.
- **워커는 비특권 계정으로 실행합니다.** sudo 권한이 없고 워커 디렉터리에만 접근하는 전용 OS 사용자를 씁니다.

자세한 내용은 [API Specification — Security](./reference/api-spec.md#security), [Worker Mode — Hardening](./architecture/worker-mode.md#hardening) 참조.

## 직접 구축하기

이 저장소는 **개념과 참조 아키텍처**를 제공합니다. 작성자 본인의 인스턴스는 개인 개발망에서 비공개로 운영되며, 여기의 패턴은 범용적입니다.

1. **블루프린트로 활용** -- CLI 도구가 있는 모든 AI 프로바이더에 적용 가능
2. **Worker 모드 패턴 채택** -- tmux + inbox/outbox 패턴은 모든 장기 실행 CLI 프로세스에 적용 가능
3. **캐싱 전략 활용** -- npm에서 [growing-pool-cache](https://www.npmjs.com/package/growing-pool-cache) 설치
4. **DB 스키마 복사** -- [참조 스키마](./reference/schema.sql)에서 세션, 메시지, 메모리, 프리셋, 캐시 테이블 제공

## 관련 프로젝트

- [growing-pool-cache](https://github.com/nskit-io/growing-pool-cache) -- AI 생성 콘텐츠를 위한 자가 성장 캐시 풀 (npm 패키지)
- [ai-native-design](https://github.com/nskit-io/ai-native-design) -- AI-Native Design 철학
- [NSKit](https://nskit.io) -- CSW와 함께 개발된 AI-Native 웹 프레임워크

## 라이선스

CC BY-NC-SA 4.0 — [LICENSE](LICENSE) 참조
