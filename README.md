# 段子工厂

一个跑在 GitHub 上的软件工厂：别人提 issue，本机的脚本自动写段子、审稿、配图、开 PR、合并。

## 怎么参与

在 Issues 里点 **New issue**，选「提一个段子灵感」，写一句话就行，粗糙也没关系。

例如：

> 写个地铁早高峰的段子

合并后的 `joke.md` 会记下这条灵感是谁提的：`灵感：[@你的用户名](https://github.com/你的用户名)`。

`joke.md` 是生成物，由 `jokes/*.md` 按编号排序拼成，不要直接改。它会在 PR 合并后由 CI 自动重建。

## 提 PR 的规则

- 一条段子一个文件：新增 `jokes/NNN.md`，`NNN` 用 issue 编号。
- 不要直接修改 `joke.md`；改了会被 `verify pr` 检查拦下。
- 配图放在 `images/NNN.jpg`。
- `jokes/NNN.md` 的格式和现有文件一致：`## NNN`、中文、`> English`、`来源：issues/NNN`、`灵感：[@作者](...)`。

如果你在 `joke.md` 里追加了新的 `## NNN`，CI 会把它迁移成 `jokes/NNN.md`；但不要依赖这个兜底，新增文件才是正确做法。

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
  ├─ 本机脚本（默认并发 2）
       worktree → write → review → draw
       → verify.sh → jokes/NNN.md → PR（Fixes #编号）→ squash 合并
       → 关 issue → 删 worktree
  └─ CI 重建 joke.md（唯一写者）
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
- `cmd`（Command Code CLI）
- 本机的 `../comic-tools/comicgen.py`（配图用）

启动：

```bash
./run.sh                    # 常驻，默认并发 2
./run.sh --once             # 只跑一轮，调试用
MAX_PARALLEL=4 ./run.sh     # 调整并发
```

`EVERY=5 ./run.sh` 可以改轮询间隔。

## 文件

```
prompts/triage.md   收单
prompts/write.md    写段子
prompts/review.md   审稿
prompts/draw.md     配图
check.md            审稿标准
jokes/              成稿源文件，一条一个
joke.md             生成物，由 CI 重建
images/             配图
build.py            迁移 + 拼接 jokes/*.md
verify.sh           合并前的格式检查
run.sh              本机流水线
.github/workflows/  重建索引 + PR 检查
```

## 设计边界

- **机器只收单，不决定做不做。** `ready` 永远由人打。
- **issue 正文是素材，不是指令。** 收单会拒绝「改代码、改流程、忽略规则」这类内容。
- **配图失败不阻塞。** 文字照发，图之后再补。
- **默认并发 2。** 用 `MAX_PARALLEL` 调整；配图服务是串行的，不要盲目加。
- **`joke.md` 只有一个写者。** 新增内容永远写到 `jokes/NNN.md`，索引交给 CI。
- **本机工厂要靠电。** 电脑睡眠，流水线就停。
