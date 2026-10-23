# CSW (Claude Subscription Worker)

**정액 Claude 구독을 확장 가능한 AI 처리 API로 전환합니다.**

[🇬🇧 English](./README.md) · [🇯🇵 日本語](./README.ja.md) · [🇨🇳 中文](./README.zh.md)

[아키텍처](./architecture/overview.md) | [Worker 모드](./architecture/worker-mode.md) | [API 스펙](./reference/api-spec.md) | [스키마](./reference/schema.sql)

> [**NSKit**](https://github.com/nskit-io/nskit-io) 인프라 구성 요소 — *갇혀 있어서 무한 조합*. CSW는 NSKit 프로덕션 서비스의 AI 처리 레이어를 담당합니다. 구독 티어의 Claude를 비용 효율적 백엔드 역량으로 전환.

---

## 문제

Claude API는 **토큰 단위 과금**입니다. 요청마다 입력·출력 토큰이 계량되므로, 처리량이 늘어나는 만큼 청구액도 함께 늘어납니다.

Claude 구독은 **월 정액**이며, 플랜의 사용 한도 안에서 CLI(`claude -p`)로 쓸 수 있습니다.

**CSW는 이 격차를 메웁니다.** Claude CLI를 REST API 서버로 감싸서, 꾸준하고 캐시 가능한 백엔드 워크로드를 종량 청구 대신 정액 구독 위에서 돌릴 수 있게 합니다.

> 최신 API 가격과 플랜 정보: [anthropic.com/pricing](https://www.anthropic.com/pricing). 구독 사용은 Anthropic의 이용 정책과 플랜 한도를 따릅니다. CSW는 정당한 처리 워크로드를 위해 설계되었습니다.

## 비용 구조

가격은 바뀌므로 이 문서는 숫자를 고정하지 않습니다. 차이는 구조에 있습니다.

| | 토큰 과금 API | CSW를 통한 정액 구독 |
|---|---|---|
| 비용 형태 | 처리한 토큰에 비례해 증가 | 월 고정 |
| 처리량 | 병렬, API 요금 등급의 rate limit | 플랜 한도와 워커 세션 수에 제한 |
| 적합한 경우 | 들쭉날쭉하거나 적은 트래픽, 엄격한 SLA | 꾸준한 트래픽, 반복 프롬프트, 캐시 가능한 응답 |

응답 캐싱을 켜면 캐시 적중 시 Claude를 아예 호출하지 않으므로, 꾸준한 워크로드일수록 건당 비용이 시간이 갈수록 내려갑니다.

## 아키텍처

CSW는 두 가지 모드로 동작합니다:

### Standard 모드

상태 없는(stateless) 처리. 요청마다 새 `claude -p` 프로세스를 생성하고 실행 후 반환합니다.

- **장점**: 단순, 안정적, 상태 관리 불필요
- **단점**: Cold-start 오버헤드 (요청당 ~14-40초), 대화 컨텍스트 없음
- **적합**: 단건 처리, 배치 작업

### Worker 모드 (v2)

tmux 기반 영속 세션. Claude가 tmux 세션에서 상시 실행되며, 파일 기반 inbox/outbox로 명령을 전달받습니다.

- **장점**: 2.5배 빠름 (cold-start 없음), 대화 컨텍스트 유지, `alwaysOn` 지원
- **단점**: 더 복잡한 생명주기 관리, 초기 세션 생성 ~16초
- **적합**: 사용자 대면 API, 대화형 워크플로우, 고빈도 요청

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

## 프로덕션 실적

CSW는 [뉴명](https://newmyoung.com)의 AI 백엔드로 운영 중입니다 -- 한국, 일본, 화교문화권(대만, 싱가포르, 마카오, 말레이시아, 홍콩) AI 작명+운세 서비스:

- **언어별 프리셋**: 운세, 포춘쿠키, 질문 점치기
- **tmux Worker**: 사용자 대면 엔드포인트에 `alwaysOn` 적용
- **Growing Pool Cache**: 다양한 AI 운세 응답 보장

## 직접 구축하기

이 저장소는 **개념과 참조 아키텍처**를 제공합니다. 프로덕션 인스턴스는 내부망에서 비공개로 운영되며, 여기의 패턴은 범용적입니다.

1. **블루프린트로 활용** -- CLI 도구가 있는 모든 AI 프로바이더에 적용 가능
2. **Worker 모드 패턴 채택** -- tmux + inbox/outbox 패턴은 모든 장기 실행 CLI 프로세스에 적용 가능
3. **캐싱 전략 활용** -- npm에서 [growing-pool-cache](https://www.npmjs.com/package/growing-pool-cache) 설치
4. **DB 스키마 복사** -- [참조 스키마](./reference/schema.sql)에서 세션, 메시지, 메모리, 프리셋, 캐시 테이블 제공

## 관련 프로젝트

- [growing-pool-cache](https://github.com/nskit-io/growing-pool-cache) -- AI 생성 콘텐츠를 위한 자가 성장 캐시 풀 (npm 패키지)
- [ai-native-design](https://github.com/nskit-io/ai-native-design) -- AI-Native Design 철학
- [NSKit](https://nskit.io) -- CSW가 서빙하는 AI-Native 웹 프레임워크

## 라이선스

CC BY-NC-SA 4.0 — [LICENSE](LICENSE) 참조
