# 一键安装脚本

```
curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-IPTV-dist/refs/heads/main/install.sh | sudo bash
```
或者
```
curl -fsSL -o install.sh https://raw.githubusercontent.com/judy-gotv/Rust-IPTV-dist/refs/heads/main/install.sh
sudo bash install.sh
```


# IPTV 管理系统 · 使用说明

多上游（M3U / Xtream Codes / Stalker Portal）聚合、自动检测择优、订阅分发、
播放代理与跳转、用户 VIP 分级、积分 / 签到 / 商城 / 卡密、Telegram 机器人、
三语言（简 / 繁 / 英）双主题 Web 管理后台。

适用对象：拥有或已获授权的直播源账号持有者，用于自建单机管理分发。
**只管理你拥有或已获授权的账号和源。**

---

## 目录

1. [安装部署](#1-安装部署)
2. [首次启动与登录](#2-首次启动与登录)
3. [初始配置](#3-初始配置)
4. [添加上游](#4-添加上游)
5. [分类勾选与同步导入](#5-分类勾选与同步导入)
6. [探测与自动择优](#6-探测与自动择优)
7. [用户与 VIP 管理](#7-用户与-vip-管理)
8. [订阅与播放](#8-订阅与播放)
9. [播放行为说明](#9-播放行为说明)
10. [积分、签到、商城、卡密](#10-积分签到商城卡密)
11. [Telegram 机器人](#11-telegram-机器人)
12. [界面：主题与语言](#12-界面主题与语言)
13. [数据备份与迁移](#13-数据备份与迁移)
14. [常见问题 FAQ](#14-常见问题-faq)
15. [安全建议](#15-安全建议)

---

## 1. 安装部署

### 1.1 二进制直接运行（推荐小 VPS）

发布包内含三个架构的静态二进制，解压后按机器选择：

| 文件 | 架构 | 适用 |
|---|---|---|
| `iptv-rs-linux-amd64` | x86_64 | 绝大多数 VPS / 云主机 |
| `iptv-rs-linux-arm64` | aarch64 | ARM 服务器（如甲骨文 ARM、树莓派 4/5、Apple Silicon 虚拟机） |
| `iptv-rs-linux-armv7` | arm 32-bit | 老款 ARM 设备（如树莓派 3） |

```bash
# 以 amd64 为例，按实际架构替换文件名；单文件二进制，前端已打包在内，放到哪都能跑
export ADMIN_USER='admin' ADMIN_PASS='你的管理员密码'
export SESSION_SECRET='随机32位以上字符串'
export PUBLIC_URL='http://你的服务器IP:8080'   # 订阅/播放链接对外地址

./iptv-rs-linux-amd64
# 看到 listening on 0.0.0.0:8080 即启动成功
```

> 单文件运行：前端 `web/` 已在编译时打包进二进制，无需额外文件。
> SQLite 数据库默认在 `./data/iptv.db`（相对工作目录）。

systemd 开机自启示例（`/etc/systemd/system/iptv-rs.service`）：

```ini
[Unit]
Description=IPTV Manager
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/iptv-rs
Environment=ADMIN_USER=admin
Environment=ADMIN_PASS=你的管理员密码
Environment=SESSION_SECRET=随机32位以上字符串
Environment=PUBLIC_URL=http://你的服务器IP:8080
ExecStart=/opt/iptv-rs/iptv-rs-linux-amd64
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload && systemctl enable --now iptv-rs
```

### 1.2 Docker 运行

```bash
export ADMIN_PASS='你的管理员密码' SESSION_SECRET='随机32位以上字符串'
export PUBLIC_URL='https://tv.example.com'
docker compose up -d --build
```

数据保存在 `./data/`（SQLite 文件）。Caddy 反代示例见 `Caddyfile`。

### 1.3 环境变量一览

| 变量 | 默认值 | 说明 |
|---|---|---|
| `BIND` | `0.0.0.0:8080` | 监听地址端口 |
| `DATABASE_URL` | `sqlite:///data/iptv.db?mode=rwc` | SQLite 路径（相对路径以启动目录为准） |
| `PUBLIC_URL` | `http://localhost:8080` | 对外地址，用于生成订阅/播放链接 |
| `SESSION_SECRET` | `dev-secret-change-me` | JWT 签名密钥，**生产必须改** |
| `ADMIN_USER` / `ADMIN_PASS` | `admin` / `changeme` | 首次启动自动建管理员 |
| `CHECK_CONCURRENCY` | `50` | 探测并发数 |
| `CHECK_BUDGET` | `50000` | 单次探测最多检测流数 |
| `FAIL_THRESHOLD` | `3` | 连续失败多少次下线 |
| `STALKER_MIN_INTERVAL_MS` | `400` | Stalker 请求最小间隔（防限流） |
| `SEED_DEMO_SHOP` | 空 | 设为 `1` 时首次启动预置 6 件演示商城商品 |

---

## 2. 首次启动与登录

浏览器打开 `http://服务器IP:8080`，用 `ADMIN_USER` / `ADMIN_PASS` 登录。
登录后先做两件事：

1. 右上角进入**系统设置**，把 `tg.bot_token` 等按需填好（见第 11 节）。
2. **修改管理员密码**：用户管理 → 找到 admin → 修改密码。

---

## 3. 初始配置

后台 **系统设置** 中的关键项（改完即时生效）：

| key | 默认值 | 说明 |
|---|---|---|
| `register.enabled` | `1` | 是否开放注册（`0` 关闭后只剩管理员手动建号） |
| `register.trial_days` | `0` | 新注册赠送订阅天数 |
| `register.invite_required` | `0` | 注册是否需要邀请码 |
| `checkin.base` | `10` | 每日签到基础积分 |
| `checkin.random_max` | `0` | 签到随机加成上限 |
| `checkin.streak_bonus` | `{"3":5,"7":20,"30":100}` | 连签 3/7/30 天额外奖励 |
| `lines.default` | `1` | 新用户默认并发路数 |
| `lines.max` | `4` | 并发路数上限 |
| `ips.max` | `0` | 单账号同时在线 IP 数（`0` 不限制） |
| `card.exchange_enabled` | `1` | 是否允许积分兑换卡密 |
| `failover.connect_timeout_s` | `4` | 回退时单个源连接超时 |
| `failover.max_candidates` | `4` | 回退候选源数量 |
| `failover.cooldown_s` | `120` | 失败源冷却时间 |
| `site.timezone` | `Asia/Shanghai` | 签到"每日"边界时区 |

---

## 4. 添加上游

进入 **上游管理** → 添加，支持三种类型（请使用你自己的授权账号）：

| 类型 | 填写字段 |
|---|---|
| M3U 订阅 | 订阅 URL |
| Xtream Codes | 主机地址（含端口）、用户名、密码 |
| Stalker Portal | 门户地址（通常以 `/c/` 结尾）、MAC 地址（`00:1A:79:XX:XX:XX` 格式） |

**批量导入**：每行一条、按空白拆分，自动识别类型——

```
http://host:8080 user pass          → Xtream（主机 用户名 密码）
http://host/c/ 00:1A:79:AA:BB:CC    → Stalker（门户 MAC）
http://example.com/list.m3u         → M3U
```

入库前会自动**测试连通性**，失败的不入库。注意：

- 为防 SSRF 攻击，添加上游时**拒绝内网 / 回环地址**（如 `127.0.0.1`、`192.168.x.x`）。
- Stalker 门户常有限流：握手成功但分类为空，多半是 IP 被限流，等几分钟再试。
- 每个上游可单独设置**播放模式**：`proxy`（服务器代理出流）或 `redirect`（302 跳转到上游直链）。

---

## 5. 分类勾选与同步导入

1. 上游添加成功后，点 **刷新分类** 拉取上游的原始分类。
2. 勾选要导入的分类（取消勾选的分类，其流与孤立频道会被清理）。
3. 点 **同步** 开始导入：频道按名称归一合并（如 `CCTV-01 高清` → `CCTV1`），
   多个上游的同名频道自动合并为多源。
4. 大上游导入是分批流式进行的，百万级频道也不会爆内存；中途重启可断点续传。

---

## 6. 探测与自动择优

- **手动探测**：频道管理 → 一键检测；或按计划任务自动跑。
- 探测给每条流打分（延迟、成功率、失败次数），**每频道每分类自动标记一条最佳流**（`is_best`），
  订阅导出与播放默认走最佳流。
- 连续失败达到 `FAIL_THRESHOLD`（默认 3 次）自动下线；恢复后自动重新上线。

---

## 7. 用户与 VIP 管理

- 用户前台可自助注册（可在设置中关闭 / 改为邀请码制），新注册默认 VIP1。
- 管理员可调整：VIP 等级（1–9，默认名 普通 / 白银 / 黄金 / 铂金 / 钻石 / 至尊 / 皇冠 / 王者 / 神话）、
  每个等级的**可用分类**（勾选）、**最大并发路数**、订阅到期时间、积分增减（走账本，有审计）。
- 订阅到期后播放链接失效，账号与积分保留，续期后恢复。
- **强制下线**：在线管理页可踢掉指定播放会话。

---

## 8. 订阅与播放

每个用户有唯一的订阅 Token（**不要公开**，泄露后可在"我的"页面重置）：

```
M3U: http://你的域名:8080/sub/{token}.m3u
TXT: http://你的域名:8080/sub/{token}.txt
EPG: http://你的域名:8080/epg.xml
```

播放器配置示例：

- **TiviMate / IPTV Pro 等**：添加播放列表，填 M3U 地址；EPG 地址填上面的 `/epg.xml`。
- **VLC**：媒体 → 打开网络串流，粘贴 M3U 地址；也可直接打开某条播放链接。
- **网页**：直接访问 M3U 地址下载，或点频道播放（走代理模式）。

订阅内容按用户 VIP 等级的**可用分类**过滤，不同等级看到不同频道。

---

## 9. 播放行为说明

- **单 IP 并发路数**（"线路"）：默认 1，上限 4。同一 IP 同时可播放的频道数；
  同一 IP 重复打开**同一频道**只续期、不占新路数；不同 IP 互不占用；IPv6 按 /64 归一。
  超限返回 `403 lines_exceeded`。
- **多源自动回退**：最佳源连不上时，自动按评分尝试次优源（候选数、超时、冷却均可在设置中调）。
  失败的源会被记 `fail_count` 并扣分，连续失败自动下线。
- **代理 vs 跳转**：按上游配置。代理模式服务器转发流量（费服务器带宽但隐藏上游）；
  跳转模式客户端直连上游（省带宽）。
- 会话（租约）持久化在数据库，**服务重启后不丢失**，播放中的线路计数不受影响。

---

## 10. 积分、签到、商城、卡密

- **签到**：网页"我的"页面或 Telegram 群内 `/checkin`，每日一次，基础积分 + 连签奖励可在设置中调。
- **商城**：用积分购买订阅天数、加线路、VIP 等级、积分包。管理员在后台配置商品（价格、库存、每人限购、最低 VIP）。
- **卡密**：管理员批量生成（类型：积分 / 天数 / VIP / 线路），用户在"我的"页面兑换；
  也可开启积分直接兑换卡密（`card.exchange_enabled`）。
- 所有积分变动走 `points_ledger` 账本，收支平衡可查，管理员调分会记审计日志。

---

## 11. Telegram 机器人

1. 用 [@BotFather](https://t.me/BotFather) 建 Bot，拿到 token。
2. 后台系统设置填 `tg.bot_token`，`tg.admin_ids` 填允许绑群的 Telegram 用户 ID（JSON 数组，如 `[123456789]`）。
3. 重启服务（或等设置热加载），Bot 开始轮询。

| 命令 | 场景 | 说明 |
|---|---|---|
| `/bindgroup` | 群内，管理员 | 把当前群设为签到群 |
| `/unbindgroup` | 群内，管理员 | 解绑 |
| `/checkin` | 已绑定的群内 | 群签到（需先在网页绑定账号，见下） |
| 私聊 Bot | 任意用户 | 按提示绑定账号 |
| `/me` | 私聊 | 查看 VIP / 积分 / 到期 / 线路 / 连签 |
| `/sub` | 私聊 | 获取个人订阅链接 |

**账号绑定**：网页"我的"页面点"绑定 Telegram"拿到一次性码 → 私聊发给 Bot → 完成绑定。
一个 Telegram 账号只能绑定一个系统账号。

---

## 12. 界面：主题与语言

- 两套 UI：**Dock**（深色原生质感）、**SaaS**（轻量卡片），后台可切换默认主题与主题色。
- 三语即时切换：简体中文 / 繁体中文 / English（网页、接口错误码、Telegram 消息同步切换）。
- 允许用户个人覆盖主题与语言（`ui.allow_user_override=1` 时）。

---

## 13. 数据备份与迁移

全部数据在一个 SQLite 文件里（默认 `./data/iptv.db`，WAL 模式）：

```bash
# 备份（WAL 模式下用 sqlite3 联机备份最稳）
sqlite3 data/iptv.db ".backup 'backup-iptv.db'"

# 迁移：停服务 → 拷走 iptv.db → 新机器同目录启动即可
# 用户 Token、租约、Stalker 会话、任务进度都在库里，重启自动恢复
```

---

## 14. 常见问题 FAQ

**Q: 添加上游提示 `url_not_allowed`？**
A: SSRF 防护拦截了内网 / 回环地址，请使用公网可访问的上游地址。

**Q: Stalker 分类拉不到？**
A: 多半是门户限流。检查 MAC 格式（`00:1A:79:XX:XX:XX`），等几分钟再点刷新分类。

**Q: 播放提示 `lines_exceeded`？**
A: 该 IP 并发路数已用满。等其他播放结束释放，或管理员给该用户加线路。

**Q: 订阅链接打不开 / 403？**
A: 检查订阅是否到期；Token 泄露后重置过则旧链接失效，用"我的"页面的新链接。

**Q: 网页打不开但 API 正常？**
A: v1.0.1 起前端已打包进二进制；旧版本需把二进制放在 `web/` 所在目录启动。

**Q: 忘记管理员密码？**
A: 停服务，用 sqlite3 改库：`UPDATE users SET pwd_hash='...' WHERE username='admin'` 不便手算哈希；
更简单：删掉 admin 行后重启，`ADMIN_USER`/`ADMIN_PASS` 环境变量会重建管理员。

**Q: 升级版本？**
A: 停服务 → 备份 `iptv.db` → 替换二进制 → 启动，migration 自动升级表结构。

---

## 15. 安全建议

- `SESSION_SECRET`、`ADMIN_PASS` 必须改成强随机值；不要用默认值上线。
- 不要把管理后台暴露在公网无鉴权端口；建议经 Caddy/Nginx 反代并加 HTTPS。
- 上游账号凭据只保存在你自己服务器的数据库里，不要发到公开群聊。
- 订阅 Token 等同于密码，泄露立即在"我的"页面重置。
- 定期备份 `iptv.db`。
