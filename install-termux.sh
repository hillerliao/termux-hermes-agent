#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Hermes Agent Termux 一键安装脚本
# 适用于: Android Termux (aarch64/arm64)
# 版本: v0.8.0
# 用法: bash install-termux.sh
# ============================================================

set -e

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ---- 配置 ----
HERMES_DIR="$HOME/hermes-agent"
REPO_URL="https://github.com/nousresearch/hermes-agent.git"
PIP_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
PIP_TRUST="pypi.tuna.tsinghua.edu.cn"

# ---- 检测 Android API Level ----
detect_android_api() {
    if [ -n "$ANDROID_API_LEVEL" ]; then
        info "ANDROID_API_LEVEL 已设置为 $ANDROID_API_LEVEL"
        return
    fi
    local level
    level=$(getprop ro.build.version.sdk 2>/dev/null || true)
    if [ -z "$level" ]; then
        warn "无法自动检测 Android API Level，使用默认值 35"
        level=35
    fi
    export ANDROID_API_LEVEL="$level"
    info "设置 ANDROID_API_LEVEL=$ANDROID_API_LEVEL"

    # 持久化到 bashrc
    if ! grep -q 'ANDROID_API_LEVEL' "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "# Hermes Agent: Android API Level for maturin/Rust builds" >> "$HOME/.bashrc"
        echo "export ANDROID_API_LEVEL=\$(getprop ro.build.version.sdk 2>/dev/null || echo 35)" >> "$HOME/.bashrc"
        info "已将 ANDROID_API_LEVEL 写入 ~/.bashrc"
    fi
}

# ---- 安装 Termux 系统包 ----
install_system_packages() {
    info "更新 Termux 软件源..."
    pkg update -y

    info "安装系统依赖..."
    pkg install -y \
        build-essential \
        clang \
        cmake \
        rust \
        python \
        nodejs \
        git \
        openssl \
        libffi \
        libsqlite \
        ca-certificates

    ok "系统依赖安装完成"
}

# ---- 配置 pip 国内镜像 ----
configure_pip_mirror() {
    info "配置 pip 清华镜像源..."
    mkdir -p "$HOME/.config/pip"
    cat > "$HOME/.config/pip/pip.conf" << EOF
[global]
index-url = ${PIP_MIRROR}
trusted-host = ${PIP_TRUST}
EOF
    ok "pip 镜像源已配置: $PIP_MIRROR"
}

# ---- 克隆仓库 ----
clone_repo() {
    if [ -d "$HERMES_DIR/.git" ]; then
        info "仓库已存在，拉取最新代码..."
        cd "$HERMES_DIR"
        git pull --ff-only || warn "git pull 失败，使用现有代码继续"
    else
        info "克隆 Hermes Agent 仓库..."
        git clone "$REPO_URL" "$HERMES_DIR"
    fi
    cd "$HERMES_DIR"
    ok "代码就绪: $HERMES_DIR"
}

# ---- 安装 Python 依赖 ----
install_python_deps() {
    info "安装 Hermes Agent 核心依赖（从源码编译，约 10-20 分钟）..."
    cd "$HERMES_DIR"

    # tee 实时输出，pipefail 捕获 pip 失败
    set -o pipefail
    pip install -e . \
        --index-url "$PIP_MIRROR" \
        --trusted-host "$PIP_TRUST" 2>&1 | tee ~/pip-install.log || {
        echo ""
        fail "核心依赖安装失败，请查看 ~/pip-install.log"
    }
    set +o pipefail

    ok "核心依赖安装完成"
}

# ---- 安装可选依赖 ----
install_optional_deps() {
    info "安装可选依赖（国内用户推荐组: cron/mcp/pty/feishu/dingtalk）..."

    # 国内用户常用，编译快（纯 Python 为主）
    local cn_extras=("cron" "mcp" "pty" "feishu" "dingtalk")
    # messaging 含 discord.py[voice]，需要编译 PyNaCl + davey (Rust)，非常慢
    # 大陆用户主要用飞书/钉钉/微信，很少用 Discord
    local slow_extras=("messaging" "slack")
    local failed=()

    for extra in "${cn_extras[@]}"; do
        info "  安装 [$extra]..."
        if pip install -e ".[$extra]" \
            --index-url "$PIP_MIRROR" \
            --trusted-host "$PIP_TRUST"; then
            ok "  [$extra] 安装成功"
        else
            warn "  [$extra] 安装失败，跳过"
            failed+=("$extra")
        fi
    done

    echo ""
    read -p "是否安装 messaging/slack (含 Discord, 需编译 Rust, 约 5-10 分钟)? [y/N] " answer
    case "$answer" in
        y|Y)
            for extra in "${slow_extras[@]}"; do
                info "  安装 [$extra]（编译较慢，请耐心等待）..."
                if pip install -e ".[$extra]" \
                    --index-url "$PIP_MIRROR" \
                    --trusted-host "$PIP_TRUST"; then
                    ok "  [$extra] 安装成功"
                else
                    warn "  [$extra] 安装失败，跳过"
                    failed+=("$extra")
                fi
            done
            ;;
        *) warn "跳过 messaging/slack（不影响飞书/钉钉/Telegram）";;
    esac

    if [ ${#failed[@]} -gt 0 ]; then
        warn "以下可选组件未安装: ${failed[*]}"
    fi
}

# ---- 验证安装 ----
verify_installation() {
    info "验证安装..."
    local hermes_bin
    hermes_bin=$(command -v hermes 2>/dev/null || true)

    if [ -z "$hermes_bin" ]; then
        fail "hermes 命令未找到"
    fi

    # 检查是否被 proot 包装脚本劫持
    if grep -q "proot-distro" "$hermes_bin" 2>/dev/null; then
        warn "检测到 hermes 入口被 proot-distro 包装脚本劫持，正在修复..."
        local python_path
        python_path=$(command -v python3 || command -v python)
        cat > "$hermes_bin" << PYEOF
#!${python_path}
import sys
from hermes_cli.main import main
if __name__ == '__main__':
    sys.argv[0] = sys.argv[0].removesuffix('.exe')
    sys.exit(main())
PYEOF
        chmod +x "$hermes_bin"
        ok "入口脚本已修复为 Termux 原生入口"
    fi

    local version_output
    version_output=$(hermes --version 2>&1 || true)
    if echo "$version_output" | grep -q "Hermes Agent"; then
        ok "Hermes Agent 安装成功!"
        echo ""
        echo "$version_output"
    else
        fail "hermes --version 输出异常: $version_output"
    fi
}

# ---- 打印后续步骤 ----
print_next_steps() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Hermes Agent 安装完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "后续步骤:"
    echo ""
    echo "  1. 配置 LLM Provider 和 API Key:"
    echo "     hermes setup"
    echo ""
    echo "  2. 或手动创建配置文件:"
    echo "     mkdir -p ~/.hermes"
    echo "     cp $HERMES_DIR/.env.example ~/.hermes/.env"
    echo "     nano ~/.hermes/.env"
    echo ""
    echo "  3. 启动 Agent:"
    echo "     hermes"
    echo ""
    echo "  4. 健康检查:"
    echo "     hermes doctor"
    echo ""
    echo -e "${YELLOW}注意事项:${NC}"
    echo "  - [voice] 功能不可用 (faster-whisper 在 ARM 上难编译)"
    echo "  - messaging/slack 默认跳过 (Discord 需编译 Rust, 很慢)"
    echo "  - 飞书/钉钉已包含在推荐可选依赖中"
    echo "  - 不要使用官方 install.sh (需要 sudo)"
    echo "  - 如果重新装 Rust 扩展，确保 ANDROID_API_LEVEL 已设置"
    echo ""
}

# ============================================================
# 主流程
# ============================================================
main() {
    echo -e "${CYAN}"
    echo "+--------------------------------------+"
    echo "|  Hermes Agent - Termux 安装脚本      |"
    echo "+--------------------------------------+"
    echo -e "${NC}"

    detect_android_api
    install_system_packages
    configure_pip_mirror
    clone_repo
    install_python_deps

    # 询问是否安装可选依赖
    echo ""
    read -p "是否安装可选依赖 (cron/mcp/pty/飞书/钉钉)? [Y/n] " answer
    case "$answer" in
        n|N) warn "跳过可选依赖";;
        *)   install_optional_deps;;
    esac

    verify_installation
    print_next_steps
}

main "$@"
