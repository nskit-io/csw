[🇬🇧 English](./README.md) · [🇰🇷 한국어](./README.ko.md) · [🇨🇳 中文](./README.zh.md)

# CSW (Claude Subscription Worker)

**月額 $200 の Claude サブスクリプションを、スケール可能な AI 処理 API に。**

> [**NSKit**](https://github.com/nskit-io/nskit-io) のインフラ構成要素 — *型にはまっているから、無限に組み合わせられる*。CSW は NSKit プロダクション・サービスの AI 処理層を担い、サブスクリプション層の Claude をコスト効率の良いバックエンド機能に転換します。

---

## 問題

Claude API はトークン従量課金です:

| モデル | 入力 | 出力 |
|-------|------|------|
| Opus | $15/M tokens | $75/M tokens |
| Sonnet | $3/M tokens | $15/M tokens |
| Haiku | $0.25/M tokens | $1.25/M tokens |

一方、Claude Max サブスクリプションは **月 $200** で CLI(`claude -p`)からほぼ無制限\*に使えます。

**CSW はこのギャップを橋渡しします**。Claude CLI を REST API サーバでラップし、サブスクリプションを本番 AI バックエンドへ転換します。

> \*Anthropic の適正使用ポリシーに従います。CSW は正当な処理ワークロード向けであり、乱用を目的としません。

---

## コスト比較

1日 1,000 リクエスト(月 30,000)、平均 2,000 トークン/リクエストの実例:

| 方式 | 月額コスト | リクエスト単価 |
|---|---|---|
| Claude API(Opus) | ~$4,500 | ~$0.15 |
| Claude API(Sonnet) | ~$900 | ~$0.03 |
| **CSW(サブスクリプション)** | **$200** | **~$0.007** |

同等作業に対し **4.5〜22 倍安い**。レスポンス・キャッシュを有効化すれば実効コストはさらに下がります(キャッシュヒットは無料)。

---

## アーキテクチャ

CSW は2つのモードで動作します:

### Standard モード

ステートレス処理。各リクエストは新しい `claude -p` プロセスを起動し、実行して返します。

- **利点**: シンプル、確実、状態管理不要
- **欠点**: コールドスタート(~14-40 秒/リクエスト)、会話文脈なし
- **向き**: ワンオフ処理、バッチジョブ

### Worker モード(v2)

永続 tmux ベース・セッション。Claude が tmux セッションで常駐し、ファイルベースの inbox/outbox 経由でコマンドを受け取ります。

- **利点**: 2.5 倍高速(コールドスタートなし)、会話文脈維持、`alwaysOn` 対応
- **欠点**: より複雑なライフサイクル管理、初期セッション作成 ~16 秒
- **向き**: ユーザー向け API、会話型ワークフロー、高頻度リクエスト

---

## 機能

- REST API(Express.js)
- MySQL によるセッション、メッセージ、メモリ、プリセット、キャッシュの永続化
- Worker Manager による並列 tmux セッション管理
- プロンプトプリセット(再利用可能なシステムプロンプト)
- レスポンス・キャッシング
- 会話メモリ(スレッド単位)

---

## NSKit での利用

NSKit プロダクション・サービスの AI 処理レイヤーとして稼働中。Gemini/GPT/Claude を混在させる代わりに、サブスクリプション・ティアで統一することでコストを予測可能にしています。

---

## 詳細と実装

完全なアーキテクチャ、API 仕様、スキーマ、Worker モード詳細、デプロイ手順は英語版を参照: **[README (English)](./README.md)** · [Architecture](./architecture/overview.md) · [API Spec](./reference/api-spec.md)

---

<div align="center">

**CSW** · Part of the **[NSKit](https://github.com/nskit-io/nskit-io)** ecosystem

© 2026 Neoulsoft Inc.

</div>
