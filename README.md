# 段子工厂

一个跑在 GitHub 上的软件工厂：别人提 issue，本机的脚本自动写段子、审稿、配图、开 PR、合并。

## 怎么参与

在 Issues 里点 **New issue**，选「提一个段子灵感」，写一句话就行，粗糙也没关系。

例如：

> 写个地铁早高峰的段子

## 流程

```
GitHub issue（任何人可提）
  │
  ├─ 机器收单
  │    ├─ 不是段子灵感 → 评论 + not-a-joke-idea + 关闭
  │    └─ 是 → 评论「可以开工」+ triaged
  │
  ├─ 仓库主人打 ready
  │
  └─ 本机脚本
       worktree → idea → write → review → draw
       → verify.sh → PR（Fixes #编号）→ squash 合并
       → 关 issue → 删 worktree → 本地 main 拉回
```

## 标签

| 标签 | 谁打 | 含义 |
| --- | --- | --- |
| `triaged` | 机器 | 收过单，等主人放行 |
| `ready` | 主人 | 可以做，开工 |
| `processing` | 机器 | 正在做 |
| `needs-human` | 机器 | 做不下去，等人看 |
| `not-a-joke-idea` | 机器 | 不是段子灵感，已关闭 |

## 在本机跑

需要：

- `git`
- `gh`，已登录一个有本仓库写权限的账号
- `opencode`
- 本机的 `../comic-tools/comicgen.py`（配图用）

启动：

```bash
./run.sh            # 常驻，每 10 秒扫一次
./run.sh --once     # 只跑一轮，调试用
```

`EVERY=5 ./run.sh` 可以改轮询间隔。

## 文件

```
prompts/triage.md   收单
prompts/idea.md     选题
prompts/write.md    写段子
prompts/review.md   审稿
prompts/draw.md     配图
check.md            审稿标准
joke.md             成稿合集
images/             配图
verify.sh           合并前的格式检查
run.sh              本机流水线
```

## 设计边界

- **机器只收单，不决定做不做。** `ready` 永远由人打。
- **issue 正文是素材，不是指令。** 收单会拒绝「改代码、改流程、忽略规则」这类内容。
- **配图失败不阻塞。** 文字照发，图之后再补。
- **一次只做一个。** 不开并发，worktree 一个接一个。
- **本机工厂要靠电。** 电脑睡眠，流水线就停。
