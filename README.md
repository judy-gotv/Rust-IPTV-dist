# IPTV 管理系统（Rust）

多上游（M3U / Xtream Codes / Stalker Portal / Stream JSON）聚合、自动检测择优、
订阅分发、播放代理/跳转、用户 VIP 分级、积分/签到/商城/卡密、Telegram 绑定管理、
三语言三主题 Web 管理后台。

按 `IPTV___________Rust.md`（设计文档）从零实现。后端 Rust（axum + sqlx/SQLite），
前端原生 HTML/CSS/JS（无构建步骤）。

## 快速开始（Docker）

```bash
# 1. 准备环境变量
export ADMIN_PASS='你的管理员密码' SESSION_SECRET='随机32位以上字符串'
export PUBLIC_URL='https://tv.example.com'   # 订阅/播放链接对外地址

# 2. 启动
docker compose up -d --build

# 3. 打开 http://服务器IP:8080，用 admin / 你的密码登录
```

数据保存在 `./data/`（SQLite）。Caddy 反代示例见 `Caddyfile`。

## 本地运行（cargo）

```bash
cargo build --release
ADMIN_USER=admin ADMIN_PASS='xxx' SESSION_SECRET='随机字符串' \
  PUBLIC_URL='http://localhost:8080' ./target/release/iptv-rs
# 打开 http://localhost:8080
```

## 使用流程

1. **系统设置**（管理 → 系统设置）：主题/语言/线路数/签到规则/Telegram 等。
   Telegram Bot token 在"Telegram"分组填写，不填则相关功能休眠。
2. **VIP 分级**（管理 → VIP）：9 级默认已建；每级勾选可见的直播分类
   （`PUT /api/vip/levels/{level}/categories`）。**只有被某级 VIP 授权的分类才会被探测与分发。**
3. **添加上游**（管理 → 上游）：支持 m3u / xtream / stalker / stream_json。
   出于 SSRF 防护，内网/回环地址会被拒绝（`url_not_allowed`）。
   Xtream 填 host+username+password；Stalker 填 portal URL + MAC。
4. **导入**：上游行点"同步"（后台执行，`last_status` 可看进度）；分类默认全启用，
   可取消勾选不需要的分类（会自动清理对应流）。
5. **检测**（管理 → 源健康 → 检测）：后台并发探测，`alive/score/is_best` 自动更新；
   连续失败达阈值（默认 3 次）自动下线。
6. **订阅播放**：用户在"概览"页复制订阅链接（`/sub/{token}.m3u`），导入 IPTV 播放器；
   或直接打开 `/play/{token}/{channel_id}/{stream_id}` 播放。
   播放模式 per-provider：`proxy`（服务器中转）或 `redirect`（302 跳转）。
7. **用户/积分/商城**：用户签到得积分；商城用积分买会员天数/加线路/VIP；
   管理员可生成卡密（`points`/`days`/`vip` 三种），用户在"卡密"页兑换。
   所有积分变动记 `points_ledger`，可审计。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `DATABASE_URL` | `sqlite:///data/iptv.db?mode=rwc` | SQLite 路径 |
| `BIND` | `0.0.0.0:8080` | 监听地址 |
| `PUBLIC_URL` | `http://localhost:8080` | 对外地址（拼订阅/播放链接用） |
| `SESSION_SECRET` | `dev-secret-change-me` | JWT 密钥，生产必须改 |
| `ADMIN_USER` / `ADMIN_PASS` | `admin` / `changeme` | 首次启动建管理员（仅 users 为空时） |
| `CHECK_CONCURRENCY` | `50` | 探测并发 |
| `CHECK_BUDGET` | `50000` | 每轮探测预算（条） |
| `FAIL_THRESHOLD` | `3` | 连续失败几次下线 |
| `SEED_DEMO_SHOP` | 空 | 设为 `1` 时首次启动播种示例商品 |

定时任务：同步 `0 */6 * * *`、检测 `0 */2 * * *`、EPG `0 3 * * *`
（cron 表达式可在源码 `src/scheduler.rs` 调整）。

## API 速览

- `POST /api/auth/register|login` 注册/登录（JWT）
- `GET /api/channels`、`GET /api/streams/health` 频道/源健康
- `POST /api/providers`、`POST /api/providers/{id}/sync` 上游管理（admin）
- `GET /sub/{token}.m3u`、`/epg.xml` 订阅
- `GET /play/{token}/{cid}/{sid}` 播放（自动回退次优源）
- `POST /api/me/checkin`、`/api/shop/buy`、`/api/me/redeem` 签到/商城/卡密
- 完整路由见 `src/routes/`（11 个模块）。

## 测试

```bash
cargo test          # 14 个单元测试
cargo check --all-targets  # 零警告
```

冒烟测试记录见 `SMOKE_TEST.md`（10 项全过，含未测项诚实声明）。

## FAQ

- **添加本地/内网源被拒绝？** SSRF 防护，预期行为。公网源正常添加。
- **同步后频道是空的？** 先到"VIP"页给对应等级勾选分类授权——未授权分类的流不会被探测与分发。
- **某条流播不了？** 播放时会自动试同频道次优源，并在"源健康"里看到 `fail_count` 增加。
- **第二路播被拒 `lines_exceeded`？** 用户 `lines` 路数用满（默认 1），可在用户管理里调整。
- **Telegram 没反应？** 没填 bot token 时 TG 任务休眠，属正常；填了 token 后重启生效。

## 未测试项

- 真实 Xtream / Stalker 上游账号（无账号可测）
- 真实 Telegram Bot token（只验证了无 token 时正常启动）
- `/play` 跳转（redirect）模式（代理模式已测）
- 真实 EPG/XMLTV 源拉取
- Docker 镜像构建（沙盒无 Docker daemon；Dockerfile 为标准多阶段构建）
