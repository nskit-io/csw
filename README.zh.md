[🇬🇧 English](./README.md) · [🇰🇷 한국어](./README.ko.md) · [🇯🇵 日本語](./README.ja.md)

# CSW (Claude Subscription Worker)

**把你自己的 Claude CLI(`claude -p`)封装成本地 REST API 的个人开发者工具。**

> [**NSKit**](https://github.com/nskit-io/nskit-io) 项目的开发者工具 — *有结构,才有无限组合*。CSW 是个人/开发用工具:让你自己的脚本和本地工具通过你本机(或私有网络)上的 REST API 调用你已登录的 Claude CLI。它不是商业或生产服务的后端。

---

## 问题

Claude API **按 token 计费**:每次请求都按输入、输出 token 计量,账单随处理量同比增长。

而 Claude 订阅是**固定月费**,可在套餐使用上限内通过 CLI(`claude -p`)使用。

**CSW 为你自己的使用封装这个 CLI**。它把 Claude CLI 放在 REST API 服务器之后,让个人脚本、本地工具和开发实验可以带着会话、预设和缓存来调用。

> **使用范围。** Claude 订阅供订阅者本人使用,须遵循 Anthropic 的使用政策与套餐上限。CSW 只用于你本人的个人与开发工作。面向其他用户的产品或服务、商业与生产负载请使用 [Claude API](https://www.anthropic.com/api)。最新 API 价格与套餐信息: [anthropic.com/pricing](https://www.anthropic.com/pricing)。

---

## 该用哪一个

| | Claude API | 通过 CSW 使用你自己的订阅 |
|---|---|---|
| 计费 | 按 token | 你本人的固定月费套餐 |
| 吞吐 | 并行,受 API 计费等级的速率限制 | 受套餐上限与 worker 会话数限制 |
| 用途 | 面向其他用户的产品与服务、商业与生产负载 | 你本人的个人与开发工作:脚本、本地工具、实验 |

启用响应缓存后,缓存命中时完全不调用 Claude,重复的本地调用更快,也更能保持在套餐上限之内。

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

- **优点**: 每次请求更快(没有每请求 ~14-40 秒的冷启动),维持会话上下文,支持 `alwaysOn`
- **缺点**: 生命周期管理更复杂,初始会话创建 ~16 秒
- **适用**: 交互式本地工具、会话式工作流、频繁请求

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

## 与 NSKit 的关系

在 NSKit 的开发工作中,作为开发者本人的本地/开发用工具而构建。它不是生产服务的后端。

---

## 详情与实现

完整架构、API 规范、数据库 schema、Worker 模式详情、部署步骤请查看英文版: **[README (English)](./README.md)** · [Architecture](./architecture/overview.md) · [API Spec](./reference/api-spec.md)

---

<div align="center">

**CSW** · Part of the **[NSKit](https://github.com/nskit-io/nskit-io)** ecosystem

© 2026 Neoulsoft Inc.

</div>
