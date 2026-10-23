[🇬🇧 English](./README.md) · [🇰🇷 한국어](./README.ko.md) · [🇯🇵 日本語](./README.ja.md)

# CSW (Claude Subscription Worker)

**把固定月费的 Claude 订阅变成可扩展的 AI 处理 API。**

> [**NSKit**](https://github.com/nskit-io/nskit-io) 的基础设施组件 — *有结构,才有无限组合*。CSW 承担 NSKit 生产服务的 AI 处理层,把订阅级别的 Claude 转化为成本高效的后端能力。

---

## 问题

Claude API **按 token 计费**:每次请求都按输入、输出 token 计量,账单随处理量同比增长。

而 Claude 订阅是**固定月费**,可在套餐使用上限内通过 CLI(`claude -p`)使用。

**CSW 就是这座桥梁**。它把 Claude CLI 封装成 REST API 服务器,让稳定、可缓存的后端负载运行在固定月费的订阅上,而不是按量计费的账单上。

> 最新 API 价格与套餐信息: [anthropic.com/pricing](https://www.anthropic.com/pricing)。订阅使用须遵循 Anthropic 的使用政策与套餐上限。CSW 面向正当处理负载,不用于滥用。

---

## 成本结构

价格会变动,因此本文档不固定具体数字。差别在于结构:

| | 按 token 计费的 API | 通过 CSW 使用固定月费订阅 |
|---|---|---|
| 成本形态 | 随处理的 token 线性增长 | 每月固定 |
| 吞吐 | 并行,受 API 计费等级的速率限制 | 受套餐上限与 worker 会话数限制 |
| 适合场景 | 流量波动大或量少、严格 SLA | 流量稳定、提示词重复、响应可缓存 |

启用响应缓存后,缓存命中时完全不调用 Claude,因此负载越稳定,单次请求成本越会随时间下降。

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

## 安全

CSW 会在宿主机上驱动 CLI 与 tmux 会话,因此应把它的 API 当作管理面来对待:

- **不要暴露到公网。** 在内网运行,并在前面放置带认证的代理或 IP 白名单。参考服务器本身没有内置认证。
- **校验所有会到达宿主机的标识符。** worker 名称必须匹配允许字符模式(`^[a-z0-9][a-z0-9-]{0,31}$`),其他值一律以 `400` 拒绝。
- **用 argv 执行,而不是 shell 字符串。** 传给 `tmux` 等外部命令的值要作为独立参数(`execFile` 方式)传入,不要拼接进命令字符串。
- **用非特权账户运行 worker。** 使用没有 sudo 权限、只能访问 worker 目录的专用系统用户。

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
