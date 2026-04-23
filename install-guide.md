# Hermes Agent 在 Termux 上的安装指南

> 经过真机实测验证（Android 12, aarch64, Termux）
> 日期：2026-04-23（更新 Rust 编译问题解决方案）

## 环境信息

- **设备**: Android 手机 (aarch64)
- **系统**: Termux (非 proot-distro Ubuntu)
- **Android API Level**: 35 (Android 12)
- **Hermes Agent 版本**: v0.10.0

---

## 第一步：安装 Termux 基础依赖

```bash
pkg update && pkg upgrade

# 编译工具链（C/Rust 扩展必需）
pkg install build-essential clang cmake rust python nodejs git

# cryptography 等包编译需要
pkg install openssl libffi libsqlite
```

## 第二步：设置关键环境变量

**这是必须的！** 否则 `jiter` 等 Rust 编写的包（maturin 构建）会报错：
`Failed to determine Android API level. Please set the ANDROID_API_LEVEL environment variable.`

```bash
# 查看你的 Android API Level
getprop ro.build.version.sdk

# 写入 bashrc 持久化
echo 'export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)' >> ~/.bashrc
source ~/.bashrc
```

## 第三步：克隆仓库

```bash
git clone https://github.com/nousresearch/hermes-agent.git ~/hermes-agent
```

## 第四步：安装核心依赖

**不要使用项目自带的 `install.sh`**，它是为标准 Linux/macOS 设计的，会尝试 `sudo apt-get` 等操作。

### 方案 A：使用预编译 wheel（推荐，快速）

```bash
cd ~/hermes-agent
export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)

# 配置 Termux 预编译 wheel 源
pip install termux-pip && tpip setup

# 安装核心依赖（pip 会自动使用预编译 wheel）
pip install -e .
```

Termux 社区提供了预编译 wheel，覆盖了大部分 Rust/C 扩展包：
- **TUR PyPI** (`termux-user-repository.github.io/pypi/`)：cryptography, pydantic-core, tiktoken, tokenizers 等
- **nsyhykui 仓库** (`nsyhykui.github.io/python_wheels_for_termux/simple/`)：500+ 预编译包

如果 `pip install -e .` 仍然失败（通常是 `jiter` 无法编译），跳到方案 B。

### 方案 B：手动安装预编译 wheel + jiter 桩

```bash
# 1. 先从预编译源安装 Rust 扩展包
pip install cryptography --index-url https://termux-user-repository.github.io/pypi/
pip install pydantic-core --index-url https://termux-user-repository.github.io/pypi/

# 2. 创建 jiter 兼容桩（jiter 无预编译 wheel，用纯 Python 替代）
python3 -c "
import site, os
sp = site.getsitepackages()[0]
with open(os.path.join(sp, 'jiter.py'), 'w') as f:
    f.write('''import json
from typing import Any, Optional, Union

def from_json(data, *, allow_inf=True, cache=True, partial_mode=None):
    if isinstance(data, (bytes, bytearray)):
        data = data.decode(\"utf-8\")
    return json.loads(data)

def to_json(obj, **kwargs):
    return json.dumps(obj, **kwargs)

class JiterError(Exception):
    pass
''')
print(f'jiter stub created at {sp}/jiter.py')
"

# 3. 安装 hermes-agent（跳过已安装的 Rust 包编译）
pip install -e . --no-build-isolation
```

### 方案 C：直接从源码编译（慢，约 10-20 分钟）

如果以上方案都不行，可以尝试直接编译（需要确保 Rust 工具链正常）：

```bash
cd ~/hermes-agent
export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)
pip install -e .
```

编译过程较慢，主要是 Rust 扩展（`jiter`, `pydantic-core`）和 C 扩展（`cryptography`, `MarkupSafe`, `pyyaml`）需要从源码编译。

## 第五步：修复 hermes 入口脚本

**关键步骤！** 如果你之前用 proot-distro 安装过，`/data/data/com.termux/files/usr/bin/hermes` 可能被覆盖为一个包装脚本（转发到 Ubuntu venv），需要恢复为 Termux 原生入口。

检查当前入口：
```bash
cat $(which hermes)
```

**如果是 proot 包装脚本**（包含 `proot-distro login ubuntu`），需要覆盖为：

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

**如果是正常的 Python 入口**（已经是 `from hermes_cli.main import main`），则无需修改。

## 第六步：按需安装可选依赖

```bash
# 消息平台集成（Telegram/Discord）
pip install -e ".[messaging]"

# 定时任务
pip install -e ".[cron]"

# MCP 协议
pip install -e ".[mcp]"

# Slack 集成
pip install -e ".[slack]"

# 钉钉/飞书
pip install -e ".[dingtalk]"
pip install -e ".[feishu]"
```

**不可用的可选组：**
- ❌ `[voice]` — `faster-whisper` 依赖 `ctranslate2`（C++），`sounddevice` 依赖 PortAudio，在 Termux ARM 上极难构建
- ❌ `[rl]` — 重量级服务端依赖

## 第七步：初始化配置

```bash
hermes setup
```

交互式配置向导会引导你设置：
1. LLM Provider（OpenAI / OpenRouter / Anthropic / 自托管）
2. API Key
3. 工具启用
4. 消息平台
5. 记忆和技能设置

或者手动创建配置：
```bash
mkdir -p ~/.hermes
cp ~/hermes-agent/.env.example ~/.hermes/.env
# 编辑 .env 填入你的 API Key
nano ~/.hermes/.env
```

## 第八步：验证安装

```bash
# 版本检查
hermes --version

# 完整诊断
hermes doctor
```

预期输出：
```
Hermes Agent v0.8.0 (2026.4.8)
Project: /data/data/com.termux/files/home/hermes-agent
Python: 3.13.12
OpenAI SDK: 2.31.0
```

## 第九步：开始使用

```bash
hermes          # 启动交互式聊天
hermes chat     # 同上
hermes status   # 查看组件状态
```

---

## 踩坑记录

### 0. Rust 扩展编译失败（jiter / pydantic-core / cryptography）

**错误**: `crate 'std' required to be available in rlib format, but was not found in this form`

**原因**: Termux 的 Rust 工具链缺少标准库 rlib 文件，导致 maturin 构建的所有 Rust 扩展包都编译失败。这是 Hermes Agent v0.10.0 最常见的安装阻断问题。

**受影响包**:
| 包名 | 类型 | 预编译 wheel |
|------|------|-------------|
| `cryptography` | Rust (maturin) | ✅ TUR 有 |
| `pydantic-core` | Rust (maturin) | ✅ TUR 有 |
| `jiter` | Rust (maturin) | ❌ 无预编译 |

**解决方案**（按优先级）:
1. 使用预编译 wheel 源（推荐）：`tpip setup` 或手动配置 `extra-index-url`
2. 对 `jiter` 创建纯 Python 兼容桩（见第四步方案 B）
3. 降级到不需要 Rust 的旧版依赖（不推荐，会丢失功能）

### 1. `ANDROID_API_LEVEL` 未设置

**错误**: `Failed to determine Android API level. Please set the ANDROID_API_LEVEL environment variable.`

**原因**: `jiter`（anthropic SDK 的依赖）使用 maturin 构建 Rust 扩展，maturin 检测到 Android 环境但无法自动获取 API Level。

**解决**: `export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)`

### 2. hermes 入口脚本被 proot 包装脚本覆盖

**错误**: `ModuleNotFoundError: No module named 'rich.console'`

**原因**: 之前用 proot-distro Ubuntu 安装时，入口脚本被改为转发到 Ubuntu venv，但 venv 里没装依赖。

**解决**: 将 `/data/data/com.termux/files/usr/bin/hermes` 恢复为 Termux 原生 Python 入口。

### 3. 不要使用官方 install.sh

**原因**: 脚本使用 `sudo apt-get` 安装系统包，Termux 用的是 `pkg`，且没有 sudo。直接 `pip install -e .` 即可。

---

## 性能说明

- **LLM API 调用**：流畅，计算在云端
- **本地处理**（技能执行、文件操作等）：可用但较慢
- **内存占用**：约 200-500MB（含 Python 运行时）
- **建议**：手机至少 4GB RAM，开启 Swap 更稳

## 磁盘空间

- 完整核心安装：约 800MB - 1.2GB
- 加上可选依赖：约 1.5 - 2GB
