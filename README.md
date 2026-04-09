# Hermes Agent - Termux 安装脚本

> 在 Android Termux 上一键安装 [Hermes Agent](https://github.com/nousresearch/hermes-agent)

## 特性

- **一键安装** — 自动安装系统依赖、克隆仓库、编译 Python/Rust 扩展
- **国内加速** — pip 清华镜像源 + GitHub 镜像自动 fallback
- **智能检测** — 自动获取 Android API Level，自动修复 proot 入口劫持
- **可选依赖** — 交互式选择安装飞书/钉钉/MCP/Telegram 等集成

## 快速开始

### 前置条件

- Android 手机（aarch64/arm64）
- [Termux](https://f-droid.org/packages/com.termux/)（从 F-Droid 安装，勿用 Play Store 版）
- 至少 2GB 可用磁盘空间
- 稳定网络连接

### 一键安装

```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/hillerliao/termux-hermes-agent/main/install-termux.sh

# 执行安装
bash install-termux.sh
```

安装过程约 15-30 分钟，主要耗时在 Rust/C 扩展编译。

### 手动安装

详见 [install-guide.md](install-guide.md)，包含逐步操作说明和踩坑记录。

## 安装后配置

```bash
# 交互式配置向导
hermes setup

# 或手动创建配置文件
mkdir -p ~/.hermes
cp ~/hermes-agent/.env.example ~/.hermes/.env
nano ~/.hermes/.env

# 启动
hermes
```

## 可选依赖

| 组件组 | 说明 | 安装耗时 |
|--------|------|---------|
| `cron` | 定时任务 | 快 |
| `mcp` | MCP 协议支持 | 快 |
| `pty` | 伪终端 | 快 |
| `feishu` | 飞书集成 | 快 |
| `dingtalk` | 钉钉集成 | 快 |
| `messaging` | Discord/Telegram | 慢（需编译 Rust） |
| `slack` | Slack 集成 | 中等 |
| `voice` | 语音识别 | ❌ ARM 不可用 |

## 已知限制

- **voice 功能不可用** — `faster-whisper` 依赖 C++ 库，ARM 上极难构建
- **不要使用官方 install.sh** — 它需要 `sudo`，Termux 没有
- **确保 ANDROID_API_LEVEL 已设置** — 否则 maturin/Rust 构建会报错
- 安装后如 hermes 命令异常，检查是否被 proot-distro 包装脚本劫持（脚本会自动修复）

## 环境要求

| 项目 | 最低要求 |
|------|---------|
| RAM | 4GB（推荐开启 Swap） |
| 磁盘 | 核心安装 ~1GB，含可选依赖 ~1.5-2GB |
| Android | API 21+（5.0+） |
| Termux | 从 F-Droid 安装 |

## 文件说明

```
.
├── README.md            # 项目说明
├── install-termux.sh    # 一键安装脚本
├── install-guide.md     # 详细安装指南（含踩坑记录）
└── LICENSE              # MIT License
```

## 致谢

- [Hermes Agent](https://github.com/nousresearch/hermes-agent) — 原始项目
- [Termux](https://termux.dev/) — Android 终端模拟器

## License

[MIT](LICENSE)
