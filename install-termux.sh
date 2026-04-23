#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Hermes Agent Termux 一键安装脚本
# 适用于: Android Termux (aarch64/arm64, Python 3.13)
# 版本: v0.10.0
# 用法: bash install-termux.sh
#
# 核心策略: 对无法编译的 Rust 扩展包 (jiter, rpds-py)
# 创建纯 Python 兼容桩 + dist-info 注册，让 pip 依赖解析通过
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
TPOIPY_INDEX="https://tpypi.loamfy-tools.workers.dev"

# 公共 pip 选项
PIP_OPTS="--index-url $PIP_MIRROR --extra-index-url $TPOIPY_INDEX --trusted-host $PIP_TRUST --trusted-host tpypi.loamfy-tools.workers.dev"
# 强制只使用预编译 wheel 的 Rust 包
PIP_BINARY_OPTS="$PIP_OPTS --only-binary=jiter --only-binary=rpds-py --only-binary=pydantic-core --only-binary=cryptography"

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
        build-essential clang cmake rust python nodejs git \
        openssl libffi libsqlite ca-certificates

    ok "系统依赖安装完成"
}

# ---- 配置 pip ----
configure_pip_mirror() {
    info "配置 pip 清华镜像源 + 预编译 wheel 源..."
    mkdir -p "$HOME/.config/pip"
    cat > "$HOME/.config/pip/pip.conf" << EOF
[global]
index-url = ${PIP_MIRROR}
extra-index-url = ${TPOIPY_INDEX}
trusted-host = ${PIP_TRUST} tpypi.loamfy-tools.workers.dev
disable-pip-version-check = true
EOF
    ok "pip 镜像源已配置"
}

# ---- 克隆仓库 ----
clone_repo() {
    if [ -d "$HERMES_DIR/.git" ]; then
        info "仓库已存在，拉取最新代码..."
        git -C "$HERMES_DIR" pull --ff-only || warn "git pull 失败，使用现有代码继续"
    else
        local mirrors=(
            "$REPO_URL"
            "https://ghproxy.cn/https://github.com/nousresearch/hermes-agent.git"
            "https://mirror.ghproxy.com/https://github.com/nousresearch/hermes-agent.git"
        )
        local cloned=false
        for mirror in "${mirrors[@]}"; do
            info "尝试克隆: $mirror"
            if git clone --depth 1 "$mirror" "$HERMES_DIR" 2>/dev/null; then
                cloned=true; break
            else
                warn "克隆失败，尝试下一个镜像..."
                rm -rf "$HERMES_DIR"
            fi
        done
        [ "$cloned" = false ] && fail "所有镜像均克隆失败，请检查网络后重试"
    fi
    ok "代码就绪: $HERMES_DIR"
}

# ---- 安装预编译 Rust 扩展包 ----
install_prebuilt_rust_wheels() {
    info "安装预编译 Rust 扩展包..."

    # cryptography (cp313-abi3 wheel)
    info "  cryptography..."
    pip install cryptography $PIP_OPTS --only-binary=cryptography 2>/dev/null \
        && ok "  cryptography 预编译安装成功" \
        || warn "  cryptography 预编译安装失败（将从源码编译）"

    # pydantic-core (cp313 wheel from tpypi)
    info "  pydantic-core..."
    pip install pydantic-core $PIP_OPTS --only-binary=pydantic-core 2>/dev/null \
        && ok "  pydantic-core 预编译安装成功" \
        || warn "  pydantic-core 预编译安装失败（将从源码编译）"
}

# ---- 创建 Rust 扩展包兼容桩 ----
create_rust_stubs() {
    info "创建 Rust 扩展包兼容桩 (jiter, rpds-py)..."
    local SP
    SP=$(python3 -c "import site; print(site.getsitepackages()[0])")

    # === jiter stub ===
    cat > "${SP}/jiter.py" << 'JITER_STUB'
"""jiter compatibility stub for Termux/Android."""
import json
from typing import Any, Optional, Union

def from_json(data, *, allow_inf=True, cache=True, partial_mode=None):
    if isinstance(data, (bytes, bytearray)):
        data = data.decode("utf-8")
    return json.loads(data)

def to_json(obj, **kwargs):
    return json.dumps(obj, **kwargs)

class JiterError(Exception):
    pass
JITER_STUB

    # jiter dist-info
    mkdir -p "${SP}/jiter-0.10.0.dist-info"
    cat > "${SP}/jiter-0.10.0.dist-info/METADATA" << 'EOF'
Metadata-Version: 2.1
Name: jiter
Version: 0.10.0
Summary: Fast iterable JSON parser (Termux stub)
Requires-Python: >=3.8
EOF
    printf 'jiter.py,,\njiter-0.10.0.dist-info/METADATA,,\njiter-0.10.0.dist-info/RECORD,,\n' > "${SP}/jiter-0.10.0.dist-info/RECORD"
    echo "termux-stub" > "${SP}/jiter-0.10.0.dist-info/INSTALLER"
    echo "jiter" > "${SP}/jiter-0.10.0.dist-info/top_level.txt"
    ok "  jiter stub 已注册 (jiter==0.10.0)"

    # === rpds-py stub ===
    mkdir -p "${SP}/rpds"
    cat > "${SP}/rpds/__init__.py" << 'RPDS_STUB'
"""rpds-py compatibility stub for Termux/Android."""
class HashTrieMap(dict):
    def insert(self, key, value):
        new = HashTrieMap(self)
        new[key] = value
        return new
    def discard(self, key):
        new = HashTrieMap(self)
        new.pop(key, None)
        return new

class HashTrieSet(frozenset):
    def insert(self, value):
        return HashTrieSet(self | {value})
    def discard(self, value):
        return HashTrieSet(self - {value})

class List(list):
    pass
RPDS_STUB

    # rpds-py dist-info
    mkdir -p "${SP}/rpds_py-0.22.0.dist-info"
    cat > "${SP}/rpds_py-0.22.0.dist-info/METADATA" << 'EOF'
Metadata-Version: 2.1
Name: rpds-py
Version: 0.22.0
Summary: Python bindings to Rust rpds crate (Termux stub)
Requires-Python: >=3.8
EOF
    printf 'rpds/__init__.py,,\nrpds_py-0.22.0.dist-info/METADATA,,\nrpds_py-0.22.0.dist-info/RECORD,,\n' > "${SP}/rpds_py-0.22.0.dist-info/RECORD"
    echo "termux-stub" > "${SP}/rpds_py-0.22.0.dist-info/INSTALLER"
    echo "rpds" > "${SP}/rpds_py-0.22.0.dist-info/top_level.txt"
    ok "  rpds-py stub 已注册 (rpds-py==0.22.0)"

    # 验证
    python3 -c "import jiter; jiter.from_json('{\"ok\":true}')" && ok "  jiter stub 验证通过"
    python3 -c "from rpds import HashTrieMap; HashTrieMap()" && ok "  rpds-py stub 验证通过"
}

# ---- 安装核心依赖 ----
install_python_deps() {
    info "安装 Hermes Agent 核心依赖..."

    # 基础构建工具
    pip install setuptools wheel $PIP_BINARY_OPTS 2>/dev/null

    # 用 --no-deps 安装 hermes-agent（避免 pip 尝试编译 Rust 包）
    info "  安装 hermes-agent (no-deps)..."
    pip install -e "$HERMES_DIR" --no-deps $PIP_OPTS 2>&1 | tail -3

    # 手动安装所有非 Rust 依赖
    info "  安装核心 Python 依赖..."
    pip install \
        "openai>=2.21.0,<3" \
        "anthropic>=0.39.0,<1" \
        "python-dotenv>=1.2.1,<2" \
        "fire>=0.7.1,<1" \
        "httpx[socks]>=0.28.1,<1" \
        "rich>=14.3.3,<15" \
        "tenacity>=9.1.4,<10" \
        "pyyaml>=6.0.2,<7" \
        "requests>=2.33.0,<3" \
        "jinja2>=3.1.5,<4" \
        "pydantic>=2.12.5,<3" \
        "prompt_toolkit>=3.0.52,<4" \
        "exa-py>=2.9.0,<3" \
        "firecrawl-py>=4.16.0,<5" \
        "parallel-web>=0.4.2,<1" \
        "fal-client>=0.13.1,<1" \
        "edge-tts>=7.2.7,<8" \
        "PyJWT[crypto]>=2.12.0,<3" \
        $PIP_BINARY_OPTS 2>&1 | tail -5

    ok "核心依赖安装完成"
}

# ---- 安装可选依赖 ----
install_optional_deps() {
    info "安装可选依赖（国内用户推荐: cron/mcp/pty/feishu/dingtalk）..."
    local cn_extras=("cron" "mcp" "pty" "feishu" "dingtalk")
    local slow_extras=("messaging" "slack")
    local failed=()

    for extra in "${cn_extras[@]}"; do
        info "  安装 [$extra]..."
        if pip install -e "$HERMES_DIR[$extra]" $PIP_BINARY_OPTS; then
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
                if pip install -e "$HERMES_DIR[$extra]" $PIP_BINARY_OPTS; then
                    ok "  [$extra] 安装成功"
                else
                    warn "  [$extra] 安装失败，跳过"
                    failed+=("$extra")
                fi
            done
            ;;
        *) warn "跳过 messaging/slack（不影响飞书/钉钉/Telegram）";;
    esac

    [ ${#failed[@]} -gt 0 ] && warn "以下可选组件未安装: ${failed[*]}"
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
    echo "  - jiter/rpds-py 使用纯 Python 兼容桩 (性能略低于 Rust 原生版)"
    echo "  - pydantic-core/cryptography 使用 tpypi 预编译 wheel"
    echo "  - [voice] 功能不可用 (faster-whisper 在 ARM 上难编译)"
    echo "  - messaging/slack 默认跳过 (Discord 需编译 Rust)"
    echo "  - 飞书/钉钉已包含在推荐可选依赖中"
    echo "  - 不要使用官方 install.sh (需要 sudo)"
    echo ""
}

# ============================================================
# 主流程
# ============================================================
main() {
    echo -e "${CYAN}"
    echo "+--------------------------------------+"
    echo "|  Hermes Agent - Termux 安装脚本      |"
    echo "|  v0.10.0 (Rust stub 兼容版)          |"
    echo "+--------------------------------------+"
    echo -e "${NC}"

    detect_android_api
    install_system_packages
    configure_pip_mirror
    clone_repo

    # 关键: 先装预编译 wheel，再创建桩，最后装 hermes
    install_prebuilt_rust_wheels
    create_rust_stubs
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
