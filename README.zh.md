[🇬🇧 English](./README.md) · [🇰🇷 한국어](./README.ko.md) · [🇯🇵 日本語](./README.ja.md)

# CSW (Claude Subscription Worker)

**把 $200/月 的 Claude 订阅变成可扩展的 AI 处理 API。**

> [**NSKit**](https://github.com/nskit-io/nskit-io) 的基础设施组件 — *有结构,才有无限组合*。CSW 承担 NSKit 生产服务的 AI 处理层,把订阅级别的 Claude 转化为成本高效的后端能力。

---

## 问题

Claude API 按 token 计费:

| 模型 | 输入 | 输出 |
|------|------|------|
| Opus | $15/M tokens | $75/M tokens |
| Sonnet | $3/M tokens | $15/M tokens |
| Haiku | $0.25/M tokens | $1.25/M tokens |

而 Claude Max 订阅 **$200/月**,通过 CLI(`claude -p`)近乎无限使用\*。

**CSW 就是这座桥梁**。它把 Claude CLI 封装成 REST API 服务器,把订阅变成生产级 AI 后端。

> \*遵循 Anthropic 合理使用政策。CSW 面向正当处理负载,不用于滥用。

---

## 成本对比

日 1,000 请求(月 30,000)、平均 2,000 tokens/请求 的实测:

| 方案 | 月成本 | 单次成本 |
|---|---|---|
| Claude API(Opus) | ~$4,500 | ~$0.15 |
| Claude API(Sonnet) | ~$900 | ~$0.03 |
| **CSW(订阅)** | **$200** | **~$0.007** |

等量工作下 **便宜 4.5~22 倍**。启用响应缓存后,有效成本进一步下降(缓存命中免费)。

---

## 架构

CSW 有两种运行模式:

### Standard 模式

无状态处理。每次请求启动一个新的 `claude -p` 进程,执行后返回。

- **优点**: 简单、可靠、无状态管理
- **缺点**: 冷启动开销(每请求 ~14-40 秒),无会话上下文
- **适用**: 一次性处理任务、批处理作业

### Worker 模式 (v2)

持久化 tmux 会话。Claude 常驻 tmux 会话,通过基于文件的 inbox/outbox 接收命令。

- **优点**: 快 2.5 倍(无冷启动),维持会话上下文,支持 `alwaysOn`
- **缺点**: 生命周期管理更复杂,初始会话创建 ~16 秒
- **适用**: 面向用户的 API、会话式工作流、高频请求

---

## 功能

- REST API(Express.js)
- MySQL 持久化会话、消息、记忆、预设、缓存
- Worker Manager 管理并行 tmux 会话
- 提示词预设(可复用系统提示)
- 响应缓存
- 会话记忆(按线程)

---

## 在 NSKit 中的作用

作为 NSKit 生产服务的 AI 处理层运行。与混用 Gemini/GPT/Claude 不同,CSW 让订阅级别提供统一能力,使成本可预测。

---

## 详情与实现

完整架构、API 规范、数据库 schema、Worker 模式详情、部署步骤请查看英文版: **[README (English)](./README.md)** · [Architecture](./architecture/overview.md) · [API Spec](./reference/api-spec.md)

---

<div align="center">

**CSW** · Part of the **[NSKit](https://github.com/nskit-io/nskit-io)** ecosystem

© 2026 Neoulsoft Inc.

</div>
