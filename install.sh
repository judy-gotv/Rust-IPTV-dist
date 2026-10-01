#!/bin/bash
# IPTV 管理系统一键安装脚本 v0.0.1
# 交互菜单: sudo bash install.sh
# 一键安装: curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-IPTV-dist/main/install.sh | sudo bash
# 非交互:   sudo bash install.sh --update | --uninstall [--purge]
#
# 环境变量(可选):
#   REPO=owner/repo      GitHub 仓库(默认 judy-gotv/Rust-IPTV-dist)
#   TAG=v0.0.1           指定版本(默认 latest)
#   INSTALL_DIR=/opt/iptv-rs
#   IPTV_SKIP_ROOT=1     跳过 root 检查(测试用)
set -euo pipefail

REPO="${REPO:-judy-gotv/Rust-IPTV-dist}"
TAG="${TAG:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/opt/iptv-rs}"
SERVICE_NAME="iptv-rs"
BIN_NAME="iptv-rs"

log()  { echo -e "\033[32m[IPTV]\033[0m $*"; }
warn() { echo -e "\033[33m[IPTV]\033[0m $*" >&2; }
die()  { echo -e "\033[31m[IPTV]\033[0m $*" >&2; exit 1; }

need_root() {
  if [ "${IPTV_SKIP_ROOT:-0}" != "1" ] && [ "$(id -u)" != "0" ]; then
    die "请用 root 运行: sudo bash $0"
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)   echo "amd64" ;;
    aarch64|arm64)   echo "arm64" ;;
    armv7l|armv7)    echo "armv7" ;;
    *) die "不支持的架构: $(uname -m)" ;;
  esac
}

# $1=文件名 → 下载到 $2 (失败返回 1)
dl() {
  local name="$1" dest="$2" url
  if [ "$TAG" = "latest" ]; then
    url="https://github.com/${REPO}/releases/latest/download/${name}"
  else
    url="https://github.com/${REPO}/releases/download/${TAG}/${name}"
  fi
  log "下载 ${name} ..."
  curl -fSL --retry 3 --retry-delay 2 -o "$dest" "$url" 2>/dev/null || return 1
}

rand_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# 是否有可用的交互终端(只检测存在不够,必须能真正打开)
has_tty() { [ -c /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; }

# 从终端读取输入,兼容 "curl ... | sudo bash" 的管道用法
tty_read() {
  if has_tty; then
    read "$@" < /dev/tty
  else
    read "$@"
  fi
}

do_install() {
  need_root
  command -v curl >/dev/null 2>&1 || die "缺少 curl，请先安装"
  local arch; arch="$(detect_arch)"
  log "检测到架构: $arch"

  mkdir -p "$INSTALL_DIR"
  local bin_tmp="$INSTALL_DIR/${BIN_NAME}.new"
  dl "iptv-rs-linux-${arch}" "$bin_tmp" || die "下载失败: https://github.com/${REPO}/releases"
  chmod +x "$bin_tmp"
  head -c 4 "$bin_tmp" | grep -q $'\x7fELF' || die "下载的文件不是有效的 ELF 二进制"
  mv -f "$bin_tmp" "$INSTALL_DIR/$BIN_NAME"
  log "二进制已安装: $INSTALL_DIR/$BIN_NAME (前端已打包在二进制内,单文件运行)"

  # ---- 交互配置 ----
  local port admin_user admin_pass public_url secret env_file="$INSTALL_DIR/env"
  if [ -f "$env_file" ]; then
    # shellcheck disable=SC1090
    . "$env_file" 2>/dev/null || true
    log "检测到已有配置，将沿用(直接回车保持原值)"
  fi
  tty_read -rp "监听端口 [${PORT:-8080}]: " port || port=""
  port="${port:-${PORT:-8080}}"
  tty_read -rp "管理员用户名 [${ADMIN_USER:-admin}]: " admin_user || admin_user=""
  admin_user="${admin_user:-${ADMIN_USER:-admin}}"
  while true; do
    tty_read -rp "管理员密码${ADMIN_PASS:+ [回车保持不变]}(明文显示): " admin_pass || admin_pass=""
    if [ -z "$admin_pass" ] && [ -n "${ADMIN_PASS:-}" ]; then admin_pass="$ADMIN_PASS"; break; fi
    [ "${#admin_pass}" -ge 6 ] && break
    warn "密码至少 6 位"
  done
  local def_url
  if [ -z "${PUBLIC_URL:-}" ]; then
    local pip
    pip="$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)"
    def_url="http://${pip:-服务器IP}:$port"
  else
    def_url="$PUBLIC_URL"
  fi
  tty_read -rp "对外访问地址 [$def_url]: " public_url || public_url=""
  public_url="${public_url:-$def_url}"
  secret="${SESSION_SECRET:-$(rand_secret)}"

  cat > "$env_file" <<EOF
# IPTV 管理系统配置(由 install.sh 生成)
PORT=$port
BIND=0.0.0.0:$port
ADMIN_USER=$admin_user
ADMIN_PASS=$admin_pass
PUBLIC_URL=$public_url
SESSION_SECRET=$secret
DATABASE_URL=sqlite://$INSTALL_DIR/data/iptv.db?mode=rwc
EOF
  chmod 600 "$env_file"
  log "配置已写入 $env_file"

  # ---- systemd 服务 ----
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=IPTV Manager (Rust)
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$env_file
ExecStart=$INSTALL_DIR/$BIN_NAME
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME"
    sleep 2
    systemctl --no-pager status "$SERVICE_NAME" | head -8 || true
  else
    warn "未检测到 systemd，请手动运行:"
    warn "  cd $INSTALL_DIR && BIND=0.0.0.0:$port DATABASE_URL=sqlite://$INSTALL_DIR/data/iptv.db?mode=rwc ./$BIN_NAME"
  fi

  echo
  log "安装完成!请妥善保存以下信息:"
  echo "  管理后台: $public_url"
  echo "  管理员账号: $admin_user"
  echo "  管理员密码: $admin_pass"
  echo "  数据目录: $INSTALL_DIR/data/  (SQLite，备份拷走 iptv.db 即可)"
  echo "  查看日志: journalctl -u $SERVICE_NAME -f"
  echo "  再次运行 sudo bash $0 可打开管理菜单(在线升级/卸载)"
}

do_update() {
  need_root
  local arch; arch="$(detect_arch)"
  log "在线升级:检查最新版(架构 $arch)..."
  local bin_tmp="$INSTALL_DIR/${BIN_NAME}.new"
  dl "iptv-rs-linux-${arch}" "$bin_tmp" || die "下载失败: https://github.com/${REPO}/releases"
  chmod +x "$bin_tmp"
  head -c 4 "$bin_tmp" | grep -q $'\x7fELF' || die "下载的文件不是有效的 ELF 二进制"
  mv -f "$bin_tmp" "$INSTALL_DIR/$BIN_NAME"
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl restart "$SERVICE_NAME"
    sleep 2
    systemctl is-active "$SERVICE_NAME" >/dev/null && log "服务已重启并运行中" || warn "服务重启后未处于运行状态，请检查日志"
  else
    warn "请手动重启服务"
  fi
  log "升级完成"
}

do_uninstall() {
  need_root
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
  fi
  if [ "${1:-}" = "--purge" ]; then
    rm -rf "$INSTALL_DIR"
    log "已卸载并清空 $INSTALL_DIR(含数据库)"
  else
    find "$INSTALL_DIR" -maxdepth 1 ! -name data ! -name env ! -path "$INSTALL_DIR" -exec rm -rf {} + 2>/dev/null || true
    log "已卸载，数据库与配置保留在 $INSTALL_DIR (清空加 --purge)"
  fi
}

show_menu() {
  need_root
  while true; do
    echo
    echo "=================================="
    echo "   IPTV 管理系统 v0.0.1"
    echo "=================================="
    echo "   1) 安装 / 重新安装"
    echo "   2) 在线升级到最新版"
    echo "   3) 卸载 (保留数据库和配置)"
    echo "   4) 卸载并清空 (删除 $INSTALL_DIR，含数据库)"
    echo "   0) 退出"
    echo "=================================="
    local choice
    tty_read -rp "请选择 [1]: " choice || choice=""
    choice="${choice:-1}"
    case "$choice" in
      1) do_install; break ;;
      2) do_update; break ;;
      3) do_uninstall; break ;;
      4)
        local yn
        tty_read -rp "将删除 $INSTALL_DIR 下全部数据(含数据库)，确认吗? [y/N]: " yn || yn=""
        if [[ "$yn" =~ ^[Yy]$ ]]; then
          do_uninstall --purge
        else
          log "已取消"
        fi
        break ;;
      0) exit 0 ;;
      *) warn "无效选项: $choice" ;;
    esac
  done
}

case "${1:-}" in
  --update)            do_update ;;
  --uninstall)         do_uninstall "${2:-}" ;;
  --menu)              show_menu ;;
  "")
    if has_tty; then
      show_menu
    else
      do_install   # 无可用终端时默认直接安装
    fi
    ;;
  *) die "未知参数: $1 (可用: --update, --uninstall [--purge], --menu)" ;;
esac
