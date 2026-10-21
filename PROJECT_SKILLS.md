# 项目级工程技能安装记录

日期：2026-10-20。按用户最新范围，仅安装 [mattpocock/skills 的 skills/engineering](https://github.com/mattpocock/skills/tree/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/engineering)。

- 固定提交：`5beb35b040e3de97e54fa9e386d7e42d15c295c2`。
- 安装位置：当前项目 `.agents/skills/<技能名>/`。
- 安装方法：Codex `skill-installer`，显式指定项目 `--dest` 与固定 `--ref`。
- 最终安装 **20 个 engineering 技能**及其目录内附带文件；其他分类的 18 个临时安装目录已核验为本次新增且内容未变后移除。
- 原有 `reverse-engineer-anything` 保留。未修改全局技能目录，也未执行这些新技能中的 setup、hooks、发布或配置操作。
- 源码版权声明：[Matt Pocock MIT License](./evidence/mattpocock-skills-LICENSE.txt)。
- 最终文件与哈希清单：[skills-import-receipt.json](./evidence/skills-import-receipt.json)。源目录发现清单可能包含其他分类，用于溯源；最终安装范围以本文件与 receipt 为准。

## 已安装

| 技能 | 项目文件 |
|---|---|
| ask-matt | [.agents/skills/ask-matt/SKILL.md](./.agents/skills/ask-matt/SKILL.md) |
| code-review | [.agents/skills/code-review/SKILL.md](./.agents/skills/code-review/SKILL.md) |
| codebase-design | [.agents/skills/codebase-design/SKILL.md](./.agents/skills/codebase-design/SKILL.md) |
| diagnosing-bugs | [.agents/skills/diagnosing-bugs/SKILL.md](./.agents/skills/diagnosing-bugs/SKILL.md) |
| domain-modeling | [.agents/skills/domain-modeling/SKILL.md](./.agents/skills/domain-modeling/SKILL.md) |
| grill-with-docs | [.agents/skills/grill-with-docs/SKILL.md](./.agents/skills/grill-with-docs/SKILL.md) |
| implement-spec | [.agents/skills/implement-spec/SKILL.md](./.agents/skills/implement-spec/SKILL.md) |
| implement | [.agents/skills/implement/SKILL.md](./.agents/skills/implement/SKILL.md) |
| improve-codebase-architecture | [.agents/skills/improve-codebase-architecture/SKILL.md](./.agents/skills/improve-codebase-architecture/SKILL.md) |
| pr | [.agents/skills/pr/SKILL.md](./.agents/skills/pr/SKILL.md) |
| prototype | [.agents/skills/prototype/SKILL.md](./.agents/skills/prototype/SKILL.md) |
| research | [.agents/skills/research/SKILL.md](./.agents/skills/research/SKILL.md) |
| retro | [.agents/skills/retro/SKILL.md](./.agents/skills/retro/SKILL.md) |
| setup-matt-pocock-skills | [.agents/skills/setup-matt-pocock-skills/SKILL.md](./.agents/skills/setup-matt-pocock-skills/SKILL.md) |
| tdd | [.agents/skills/tdd/SKILL.md](./.agents/skills/tdd/SKILL.md) |
| to-spec | [.agents/skills/to-spec/SKILL.md](./.agents/skills/to-spec/SKILL.md) |
| to-tickets | [.agents/skills/to-tickets/SKILL.md](./.agents/skills/to-tickets/SKILL.md) |
| triage | [.agents/skills/triage/SKILL.md](./.agents/skills/triage/SKILL.md) |
| wayfinder | [.agents/skills/wayfinder/SKILL.md](./.agents/skills/wayfinder/SKILL.md) |
| wizard | [.agents/skills/wizard/SKILL.md](./.agents/skills/wizard/SKILL.md) |

## 使用边界

新技能预计在下一轮被项目技能发现机制识别；含 `disable-model-invocation: true` 的入口保留上游的显式调用约定。部分技能面向 Claude Code、TypeScript 或 issue tracker，其可执行性取决于届时环境与用户任务，不代表当前 Swift 工程已经配置相关依赖。

`grill-with-docs` 是一个兼容入口，原文会调用 `grilling` 和 `domain-modeling`。其中 `grilling` 位于上游 productivity 分类，本次按要求未安装；`ask-matt` 等路由入口也可能提到范围外的技能。这里保留原文和范围限制，不为补依赖而扩大安装范围。


## Stitch（2026-10-21 新增）

按 [Stitch 官方 CLI / MCP / Skills 文档](https://stitch.withgoogle.com/docs/cli/mcp-and-skills/) 安装：

- `@google/stitch@0.11.1` 固定为项目开发依赖；安装时禁用生命周期脚本。
- [Stitch skill](./.agents/skills/stitch/SKILL.md)：1 个 skill，附带设计同步、界面评审等共 18 个文件；使用官方 CLI 的项目安装命令生成。
- 项目 MCP：`.codex/config.toml` 中 `stitch`；保留 REA。
- `npm run stitch -- <命令>` 通过项目启动器执行，并将配置、凭据和安装状态隔离到已忽略的 `.stitch-cli/`。
- 握手通过，提供 7 个工具；[验证记录](./evidence/stitch-mcp-handshake.json)、[安装记录](./evidence/stitch-install-receipt.json)。未调用创建、上传、生成或删除工具。

2026-10-21 已完成项目隔离认证与设计迁移，详见 [Stitch 设计交接](./docs/design/STITCH_HANDOFF.md)。需要重新认证时，在当前项目终端运行 `npm run stitch -- login`，并由用户完成 Google 登录/授权。也可通过 `STITCH_API_KEY` 环境变量提供凭据，勿把密钥写入项目文档或 MCP 配置。检查状态：`npm run stitch -- status --json`。

新 skill 预计下一轮可被发现。MCP 需重新加载/重启当前项目会话；Codex 仅在受信任项目加载项目级 `.codex/config.toml`。未修改全局信任或配置。


## in-your-own-words（2026-10-21 新增）

已从 [cursor/plugins 固定提交](https://github.com/cursor/plugins/tree/019a6a20592c10bf92869e5740368f578a9997fd/pstack/skills/in-your-own-words) 安装到项目 [.agents/skills/in-your-own-words/SKILL.md](./.agents/skills/in-your-own-words/SKILL.md)。仅安装该 skill，未安装整个 pstack 插件，未修改全局配置。新技能预计下一轮可发现。文件校验见 [安装记录](./evidence/in-your-own-words-install-receipt.json)。
