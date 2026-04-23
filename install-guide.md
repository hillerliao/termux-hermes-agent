# Hermes Agent 在 Termux 上的安装指南

> 经过真机实测验证（Android 12, aarch64, Termux, Python 3.13）
> 日期：2026-04-23（更新 Rust 编译问题完整解决方案）

## 环境信息

- **设备**: Android 手机 (aarch64)
- **系统**: Termux (非 proot-distro Ubuntu)
- **Android API Level**: 35 (Android 12)
- **Hermes Agent 版本**: v0.10.0
- **Python**: 3.13.x

---

## 核心挑战：Rust 扩展包编译失败

Hermes Agent v0.10.0 的依赖链中有 3 个 Rust 扩展包在 Termux 上**无法编译**：

| 包名 | 用途 | 预编译 wheel | 解决方案 |
|------|------|-------------|---------|
| `jiter` | JSON 解析 (openai/anthropic 依赖) | ❌ 无 | 纯 Python 兼容桩 |
| `rpds-py` | 不可变数据结构 (jsonschema 依赖) | ❌ 无 | 纯 Python 兼容桩 |
| `pydantic-core` | 数据验证核心 | ✅ tpypi 有 | 预编译 wheel |
| `cryptography` | 加密 (PyJWT 依赖) | ✅ tpypi 有 | 预编译 wheel |

**编译失败原因**: Termux 的 Rust 工具链缺少标准库 rlib 文件，所有 maturin 构建都会报错：`crate 'std' required to be available in rlib format`

---

## 第一步：安装 Termux 基础依赖

```bash
pkg update && pkg upgrade

pkg install build-essential clang cmake rust python nodejs git openssl libffi libsqlite
```

## 第二步：设置 ANDROID_API_LEVEL

```bash
export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)
echo 'export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)' >> ~/.bashrc
source ~/.bashrc
```

## 第三步：克隆仓库

```bash
git clone https://github.com/nousresearch/hermes-agent.git ~/hermes-agent
```

## 第四步：安装预编译 Rust wheel + 兼容桩

### 方案 A：一键安装脚本（推荐）

```bash
curl -O https://raw.githubusercontent.com/hillerliao/termux-hermes-agent/main/install-termux.sh
bash install-termux.sh
```

### 方案 B：手动分步安装

```bash
# 1. 安装 termux-pip 配置预编译源
pip install termux-pip && tpip setup

# 2. 安装预编译 Rust wheel
pip install cryptography --only-binary=cryptography
pip install pydantic-core --only-binary=pydantic-core

# 3. 创建 jiter 兼容桩
SP=$(python3 -c "import site; print(site.getsitepackages()[0])")
cat > "${SP}/jiter.py" << 'EOF'
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
EOF

# 注册 jiter 桩为已安装包 (让 pip 依赖解析通过)
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

# 4. 创建 rpds-py 兼容桩
mkdir -p "${SP}/rpds"
cat > "${SP}/rpds/__init__.py" << 'EOF'
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
EOF

# 注册 rpds-py 桩
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

# 5. 验证桩
python3 -c "import jiter; print(jiter.from_json('{\"ok\":true}'))"
python3 -c "from rpds import HashTrieMap; print(HashTrieMap())"
```

## 第五步：安装 Hermes Agent

```bash
cd ~/hermes-agent

# 用 --no-deps 安装，避免 pip 尝试编译 Rust 包
pip install -e . --no-deps

# 手动安装所有非 Rust 依赖
PIP_OPTS="--only-binary=jiter --only-binary=rpds-py --only-binary=pydantic-core --only-binary=cryptography"
pip install \
    "openai>=2.21.0,<3" "anthropic>=0.39.0,<1" \
    "python-dotenv>=1.2.1,<2" "fire>=0.7.1,<1" \
    "httpx[socks]>=0.28.1,<1" "rich>=14.3.3,<15" \
    "tenacity>=9.1.4,<10" "pyyaml>=6.0.2,<7" \
    "requests>=2.33.0,<3" "jinja2>=3.1.5,<4" \
    "pydantic>=2.12.5,<3" "prompt_toolkit>=3.0.52,<4" \
    "exa-py>=2.9.0,<3" "firecrawl-py>=4.16.0,<5" \
    "parallel-web>=0.4.2,<1" "fal-client>=0.13.1,<1" \
    "edge-tts>=7.2.7,<8" "PyJWT[crypto]>=2.12.0,<3" \
    $PIP_OPTS
```

## 第六步：修复 hermes 入口脚本（如需要）

```bash
cat $(which hermes)
```

如果是 proot 包装脚本，覆盖为：

```bash
cat > $(which hermes) << 'EOF'
#!/data/data/com.termux/files/usr/bin/python3.13
import sys
from hermes_cli.main import main
if __name__ == '__main__':
    sys.argv[0] = sys.argv[0].removesuffix('.exe')
    sys.exit(main())
EOF
chmod +x $(which hermes)
```

## 第七步：安装可选依赖

```bash
# 国内用户常用
pip install -e ".[cron]" $PIP_OPTS
pip install -e ".[mcp]" $PIP_OPTS
pip install -e ".[pty]" $PIP_OPTS
pip install -e ".[feishu]" $PIP_OPTS
pip install -e ".[dingtalk]" $PIP_OPTS
```

**不可用**: `[voice]`（C++ 依赖）、`[rl]`（重量级服务端）

## 第八步：验证安装

```bash
hermes --version
hermes doctor
```

预期输出：
```
Hermes Agent v0.10.0 (2026.4.16)
Project: /data/data/com.termux/files/home/hermes-agent
Python: 3.13.13
OpenAI SDK: 2.32.0
```

---

## 踩坑记录

### 0. Rust 扩展编译失败（jiter / pydantic-core / rpds-py / cryptography）

**错误**: `crate 'std' required to be available in rlib format, but was not found in this form`

**原因**: Termux 的 Rust 工具链缺少标准库 rlib 文件，maturin 构建的所有 Rust 扩展包都编译失败。

**解决方案**:
1. `pydantic-core` / `cryptography` → tpypi 预编译 wheel
2. `jiter` / `rpds-py` → 纯 Python 兼容桩 + dist-info 注册
3. 安装时用 `--no-deps` 避免 pip 自动编译 Rust 包
4. 用 `--only-binary=jiter --only-binary=rpds-py` 让 pip 不尝试从源码编译

### 1. ANDROID_API_LEVEL 未设置

**错误**: `Failed to determine Android API level`

**解决**: `export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)`

### 2. hermes 入口脚本被 proot 包装脚本覆盖

**错误**: `ModuleNotFoundError: No module named 'rich.console'`

**解决**: 将 `/data/data/com.termux/files/usr/bin/hermes` 恢复为 Termux 原生 Python 入口。

### 3. 不要使用官方 install.sh

**原因**: 脚本使用 `sudo apt-get` 安装系统包，Termux 用的是 `pkg`，且没有 sudo。

### 4. 预编译源兼容性

| 源 | Python 版本 | 架构 | 可用性 |
|----|-----------|------|--------|
| **tpypi (loamfy)** | cp313 | android_24_arm64 | ✅ 可用 |
| TUR (termux-user-repository) | cp311 | linux_aarch64 | ❌ Python 版本不匹配 |
| nsyhykui | cp313 | android_24_arm64 | ❌ wheel 文件 404 |

### 5. jiter/rpds-py 桩必须注册 dist-info

如果不注册 dist-info，pip 的依赖解析器会认为这些包未安装，导致 `ResolutionImpossible` 错误。注册方法是在 `site-packages/` 下创建 `jiter-0.10.0.dist-info/` 和 `rpds_py-0.22.0.dist-info/` 目录。

---

## 性能说明

- **LLM API 调用**：流畅，计算在云端
- **本地处理**：可用但较慢（jiter/rpds 使用纯 Python 桩，性能低于 Rust 原生版）
- **内存占用**：约 200-500MB（含 Python 运行时）
- **建议**：手机至少 4GB RAM，开启 Swap 更稳

## 磁盘空间

- 完整核心安装：约 800MB - 1.2GB
- 加上可选依赖：约 1.5 - 2GB
