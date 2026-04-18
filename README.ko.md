# CSW (Claude Subscription Worker)

**월 $200 Claude 구독을 확장 가능한 AI 처리 API로 전환합니다.**

[🇬🇧 English](./README.md) · [🇯🇵 日本語](./README.ja.md) · [🇨🇳 中文](./README.zh.md)

[아키텍처](./architecture/overview.md) | [Worker 모드](./architecture/worker-mode.md) | [API 스펙](./reference/api-spec.md) | [스키마](./reference/schema.sql)

> [**NSKit**](https://github.com/nskit-io/nskit-io) 인프라 구성 요소 — *갇혀 있어서 무한 조합*. CSW는 NSKit 프로덕션 서비스의 AI 처리 레이어를 담당합니다. 구독 티어의 Claude를 비용 효율적 백엔드 역량으로 전환.

---

## 문제

Claude API는 토큰 기반 과금입니다:

| 모델 | Input | Output |
|-------|-------|--------|
| Opus | $15/M tokens | $75/M tokens |
| Sonnet | $3/M tokens | $15/M tokens |
| Haiku | $0.25/M tokens | $1.25/M tokens |

Claude Max 구독은 **월 $200**으로 CLI(`claude -p`)를 통한 무제한\* 사용이 가능합니다.

**CSW는 이 격차를 메웁니다.** Claude CLI를 REST API 서버로 감싸서, 구독을 프로덕션 AI 백엔드로 전환합니다.

> \*Anthropic의 공정 사용 정책 적용. CSW는 정당한 처리 워크로드를 위해 설계되었습니다.

## 비용 비교

**하루 1,000건** (~월 30,000건), 요청당 평균 ~2,000 토큰 기준 실제 계산:

| 방식 | 월 비용 | 건당 비용 |
|------|---------|----------|
| Claude API (Opus) | ~$4,500 | ~$0.15 |
| Claude API (Sonnet) | ~$900 | ~$0.03 |
| **CSW (구독)** | **$200** | **~$0.007** |

동일 작업 대비 **4.5~22배 저렴**합니다. 응답 캐싱을 활성화하면 캐시된 응답은 비용이 0이므로 실질 비용은 더 낮아집니다.

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
| **히스토리 압축** | 메시지 임계치 초과 시 Haiku로 자동 요약 |
| **Worker 헬스** | 30초 주기 체크, 행 감지 시 자동 재시작, 서버 재부팅 시 복원 |

## API 개요

| 메서드 | 엔드포인트 | 설명 |
|--------|----------|------|
| `POST` | `/api/v1/process` | AI 요청 처리 (stateless/새 세션/기존 세션) |
| `GET` | `/api/v1/sessions` | 세션 목록 |
| `GET/POST` | `/api/v1/sessions/:id/memory` | 세션 메모리 조회/설정 |
| `GET/POST` | `/api/v1/presets` | 프리셋 목록/생성 |
| `POST` | `/api/v1/workers` | Worker 생성 |
| `GET` | `/api/v1/workers` | Worker 목록 |

전체 스펙은 [API Specification](./reference/api-spec.md) 참조.

## 프로덕션 실적

CSW는 [뉴명](https://newmyoung.com)의 AI 백엔드로 운영 중입니다 -- 한국, 일본, 화교문화권(대만, 싱가포르, 마카오, 말레이시아, 홍콩) AI 작명+운세 서비스:

- **9개 프리셋**: 운세, 포춘쿠키, 질문 점치기 (언어별 3개씩)
- **tmux Worker**: 사용자 대면 엔드포인트에 `alwaysOn` 적용
- **Growing Pool Cache**: 다양한 AI 운세 응답 보장
- **월 17,000+ 건**: 실질 건당 비용 ~$0.01

## 직접 구축하기

이 저장소는 **개념과 참조 아키텍처**를 제공합니다. 프로덕션 CSW는 csw.nskit.io에서 운영되지만, 여기의 패턴은 범용적입니다.

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
