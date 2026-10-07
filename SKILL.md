---
name: twitter-cli
description: Read and post X/Twitter content via twitter-cli — feed, bookmarks, search, user profiles, and tweets. Use when the user asks to check X timeline or bookmarks, search for tweets, view a profile, post a tweet, or access any X feature. Do not use for installing the CLI or setting up the proxy.
---

# Twitter CLI Skill

Interact with X (Twitter) using the pre-installed `twitter-cli`. Handles auth token validation and tells the user to refresh credentials when needed.

## This Machine's Environment

| Item | Value |
|------|-------|
| CLI exe | `C:\Users\Administrator\.local\bin\twitter.exe` |
| Install method | `uv tool install twitter-cli --default-index https://pypi.tuna.tsinghua.edu.cn/simple` |
| Auth source | User-level env vars `TWITTER_AUTH_TOKEN` + `TWITTER_CT0` (set via `setx`) |
| Proxy | `TWITTER_PROXY=http://127.0.0.1:7897` (Vortex on WinINET, Node MCP 不继承) |
| Sandbox | Trae sandbox blocks `C:\Users\Administrator\.twitter-cli` cache — **all commands require `dangerouslyDisableSandbox: true`** |

## Before Every Command — Set Env Vars from Registry

**Never** hardcode `TWITTER_AUTH_TOKEN` or `TWITTER_CT0` directly in Shell command text (the sandbox blocks embedding credentials outside the local environment). Always read from the Windows registry:

```powershell
$env:TWITTER_AUTH_TOKEN = [Environment]::GetEnvironmentVariable("TWITTER_AUTH_TOKEN", "User")
$env:TWITTER_CT0       = [Environment]::GetEnvironmentVariable("TWITTER_CT0", "User")
$env:TWITTER_PROXY     = [Environment]::GetEnvironmentVariable("TWITTER_PROXY", "User")
```

Run those three lines at the top of every Shell invocation, then call the CLI.

## Token Validity Check — Run This First

Before any read or write, run a cheap auth probe to catch expired credentials early. This matters because X silently returns empty data for expired cookies rather than a clear error.

```powershell
# Probe — exits 0 if auth is good, non-zero if expired
& "C:\Users\Administrator\.local\bin\twitter.exe" -c bookmarks --max 1 2>$null | Out-Null; "probe exit=$LASTEXITCODE"
```

| Exit | Meaning | Action |
|------|---------|--------|
| `0` | Auth OK | Proceed to the user's request |
| `1` with `not_authenticated` in stderr | Cookies missing | See **Token Refresh** below |
| `401` / `403` HTTP errors | Credentials expired | See **Token Refresh** below |
| No output (empty JSON) | 可能失效也可能刚好没书签 | Run `twitter -c whoami` to confirm — if that also returns nothing, treat as expired |

### Token Refresh — This Is When You Tell the User

**Do not** try to fix credentials automatically. These cookies are tied to the user's X account and are secret. When refresh is needed, respond like this:

```
⚠️ 你的 X 登录凭据已过期。请按以下步骤重新获取：

1. 用 Chrome/Edge 打开 https://x.com 并确保已登录你的账号
2. 按 F12 打开开发者工具 → Application 标签 → 左侧 Cookies → 点 https://x.com
3. 在右侧列表里找到这两个值：
   - auth_token  （一长串十六进制）
   - ct0          （也是一长串十六进制）
4. 把这两个值发给我（注意：不要贴到公开场合或 commit 到 git）

我会帮你执行：
  setx TWITTER_AUTH_TOKEN "你给的值"
  setx TWITTER_CT0 "你给的值"

设置完后重开一个终端即可生效。
```

**安全约束**：
- 不要把 `auth_token` / `ct0` 明文写入任何文件、脚本或命令历史
- 从用户消息拿到值后，直接传给 `setx` 即可，中间变量用 `[Environment]::GetEnvironmentVariable(..., "User")` 读
- 如果用户说"我没有这两个 cookie"，指导他从浏览器 Cookie 面板找到 `auth_token` 和 `ct0` 这两个 name 列

## Common Commands

All examples assume you have already set the three env vars at the top of the Shell command.

| Task | Command | Notes |
|------|---------|-------|
| 首页时间线 (For You) | `twitter -c feed --max 20` | `-c` = 紧凑 JSON，LLM 友好 |
| 关注流 | `twitter -c feed -t following --max 20` | |
| 书签 | `twitter -c bookmarks --max 25` | 手动收藏的推文 |
| 搜索 | `twitter -c search "keyword" -t Latest --max 30` | `-t Top/Latest/Media/People` |
| 用户资料 | `twitter -c user elonmusk` | |
| 用户推文 | `twitter -c user-posts elonmusk --max 20` | |
| 用户点赞 | `twitter -c likes elonmusk --max 20` | |
| 推文详情+回复 | `twitter -c tweet 1234567890` | 也可传 URL |
| 发推 | `twitter post "hello world"` | |
| 发推带图 | `twitter post "caption" --image C:\path\img.jpg` | 最多 4 张 |
| 删除推文 | `twitter delete 1234567890` | 只能删自己的 |
| 点赞/取消 | `twitter like 1234567890` / `twitter unlike 1234567890` | |
| 重新抓取 last feed 第 N 条 | `twitter -c show 3` | |
| 认证状态 | `twitter status` | 验证 cookie 是否有效 |

### Flags Cheat Sheet

| Flag | Meaning |
|------|---------|
| `-c` / `--compact` | JSON 单行输出（推荐给 LLM） |
| `--full-text` | 不截断推文正文 |
| `--max N` | 拉取 N 条 |
| `--json` | 结构化输出（非 TTY 自动 YAML） |
| `--yaml` | 强制 YAML |
| `-t Latest` | search 的 Latest / Top / Media / People |
| `--from username` | search 指定作者 |
| `--since 2026-10-01` | search 时间过滤 |

## Execution Checklist

For **any** twitter-cli command you run on this machine:

1. ✅ Top of Shell command block — read `TWITTER_AUTH_TOKEN`, `TWITTER_CT0`, `TWITTER_PROXY` from registry with `[Environment]::GetEnvironmentVariable(..., "User")`
2. ✅ Set `dangerouslyDisableSandbox: true` on the Shell tool call (Trae sandbox blocks `~\.twitter-cli` cache dir)
3. ✅ If the command writes data to a file (e.g. `twitter -c bookmarks --max 50 > bookmarks.json`), redirect inside the same shell
4. ✅ On exit code 1 with `not_authenticated` — tell the user to refresh tokens using the script in **Token Refresh** above. Do not retry blindly.
5. ⚠️ The warning `Failed to init ClientTransaction: 'NoneType' object has no attribute 'group'` appears on every run — it is harmless, a known twitter-cli issue, read operations still succeed. Ignore it.
6. ⚠️ The auth probe itself may also emit that warning. Use `2>$null` to suppress stderr noise.

## Edge Cases

| Situation | Handling |
|-----------|----------|
| 沙箱禁止写 `C:\Users\Administrator\.twitter-cli` | 必须 `dangerouslyDisableSandbox: true`，否则命令直接失败 |
| 命令返回空 list 不是报错 | `bookmarks --max 1` 对新号就是空。用 `twitter status` 确认 auth 状态 |
| 退出码 -1 但 JSON `ok: true` | Twitter CLI 把 stderr 警告也算进 PowerShell 错误码，忽略非零 exit code，检查 JSON body |
| Token 突然失效 | 401/403 直接告诉用户去浏览器取新 auth_token/ct0，不要自动重试 |
| 用户问 "浏览历史" (x.com/i/history) | 这是 2026-05 新 History 标签页（书签+点赞+看过的视频+文章），CLI 无直接命令，可用 bookmarks + likes 组合模拟 |
| 代理不通 | 如果出现 TLS 超时 / 连接失败，先检查 Vortex（`127.0.0.1:7897`）是否在跑，Google 系域名需要换代理节点 |
