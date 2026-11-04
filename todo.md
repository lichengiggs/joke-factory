# 并发化改造 TODO

状态：已实施（2026-11-04）；并发 4 条测试通过，见文末“实施记录”。
目标：`run.sh` 能并发处理多个 `ready` issue；`joke.md` 不因合并冲突阻塞；配图服务不被打爆。

---

## 1. 结论（先看这里）

采用以下方案，不要再引入 merge queue、发布锁或自定义合并机器人：

1. **一单一个文件**：`jokes/NNN.md` 是事实源，`joke.md` 是生成物。
2. **CI 是唯一写者**：GitHub Action 在 push 到 main 后运行 `build.py`，重建并提交 `joke.md`。
3. **`run.sh` 不写 main**：只 `git fetch`，worker 从 `origin/main` 建 worktree，PR 只加 `jokes/NNN.md` 和图片。
4. **并发先开 2**：`MAX_PARALLEL=2`，稳定后再考虑 3。
5. **配图侧只限流**：远端 Xinference 本身串行，不要靠加 worker 或加模型副本提吞吐。

核心原则：**消除共享写入点，而不是给共享写入点加锁。**

---

## 2. 背景与已确认事实

### 2.1 `joke.md` 冲突

- 多个 PR 都往 `joke.md` 末尾追加，Git 必然产生 `UU joke.md`（已在临时仓库复现）。
- 当前 main **没有分支保护**，也没有 merge queue / auto-merge。
- 分支保护只能决定“能不能合、什么时候合”，**不能解决内容冲突**；merge queue 也不会解冲突。
- 所以必须改数据结构，不是改 GitHub 设置。

### 2.2 配图服务

- 远端是 Xinference + diffusers，只有一个 `qwen-image-rep0` 副本，单卡 GPU0，nf4 量化。
- `xinference/core/model.py`：`allow_batch=False` 时用 `asyncio.Lock` 串行化请求。
- diffusers 图像模型没有设置 `allow_batch=True`，所以**所有画画请求在服务端排队执行**。
- 启动参数 `request_limits=None`，队列无上限；并发不会直接 OOM 或 429。
- 实测单张 38–46 秒（不是 README 的 7–8 秒），一单完整流程约 2.5 分钟。
- 并发 N 个时，最后一个要等大约 `(N-1) × 40s`；`comicgen.py` 默认 `--timeout 300`。
- 结论：服务不会被打死，但加 worker 不会提高画图吞吐；按 Amdahl 定律，串行段决定上限。

### 2.3 当前 `run.sh` 的并发障碍

- 单 PID 守卫，只能一个实例。
- `scan_ready` 只取 `head -1`。
- 每个 worker 结束都会在仓库根目录 `git checkout main && git pull`，并发会互相踩。
- 多个 worker 同时追加 `joke.md` 会冲突。
- 没有原子领单，可能重复处理同一个 issue。

---

## 3. 目标结构

```text
jokes/001.md          # 单条完整 section：## NNN、中文、英文、来源、灵感
jokes/003.md
images/001.jpg
images/001.json
joke.md               # 生成物，不手改
build.py              # 迁移 + 排序拼接
verify.sh NNN         # 校验 jokes/NNN.md + images/NNN.*
run.sh                # 只做流水线，不写 main
.github/workflows/rebuild-joke.yml
```

`joke.md` 由 `jokes/*.md` 按编号排序生成。两个 PR 改不同文件，合并顺序无所谓。

---

## 4. 任务清单

### T1. 新增 `build.py`

- [ ] 实现 `migrate()`：读取 `joke.md`，把其中还没有对应 `jokes/NNN.md` 的 `## NNN` 抽成文件。
- [ ] 实现 `build()`：按数字编号排序，拼接 `jokes/*.md` 生成 `joke.md`。
- [ ] 输出必须**确定性**：不能有时间戳、随机数、当前分支名。
- [ ] 过滤非数字文件名，避免 `int(p.stem)` 报错。
- [ ] 重复编号只保留第一次，并打印提示。

参考实现：

```python
#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
JOKES = ROOT / "jokes"
INDEX = ROOT / "joke.md"
SECTION = re.compile(r"^## (\d+)\s*$", re.M)


def sections(text):
    found = list(SECTION.finditer(text))
    for i, match in enumerate(found):
        end = found[i + 1].start() if i + 1 < len(found) else len(text)
        yield match.group(1), text[match.start():end].strip() + "\n"


def migrate():
    if not INDEX.exists():
        return
    known = {p.stem for p in JOKES.glob("*.md") if p.stem.isdigit()}
    for number, body in sections(INDEX.read_text(encoding="utf-8")):
        if number in known:
            continue
        (JOKES / f"{number}.md").write_text(body, encoding="utf-8")
        known.add(number)
        print(f"migrated ## {number}")


def build():
    files = sorted(
        (p for p in JOKES.glob("*.md") if p.stem.isdigit()),
        key=lambda p: int(p.stem),
    )
    body = "\n".join(p.read_text(encoding="utf-8").strip() + "\n" for p in files)
    INDEX.write_text("# 段子集\n\n" + body, encoding="utf-8")


if __name__ == "__main__":
    JOKES.mkdir(exist_ok=True)
    migrate()
    build()
```

验收：首次运行完成历史迁移，`build.py` 连续运行两次，第二次不产生任何改动。

### T2. 拆分现有数据

- [ ] 建 `jokes/`。
- [ ] 直接运行 `python3 build.py`，用 T1 的 `migrate()` 拆分现有 `joke.md`。
- [ ] 确认生成的 `joke.md` 与原来内容一致（顺序可能变成按编号排序，这是预期）。
- [ ] 提交 `jokes/*.md`。

### T3. 改 `verify.sh`

- [ ] 参数仍为 `NNN`。
- [ ] 检查 `jokes/NNN.md` 存在，且包含 `## NNN`。
- [ ] 检查英文引用行 `^> `。
- [ ] 检查 `灵感：[@`。
- [ ] 检查 `images/NNN.jpg` 或 `images/NNN.png` 存在且不是空文件。
- [ ] 检查图片格式为 JPEG/PNG。
- [ ] 检查 `jokes/NNN.md` 里没有 `## 自评`。
- [ ] **不要**再依赖 `joke.md` 里有这一节；PR 阶段 `joke.md` 本来就是旧的。

### T4. 改 `run.sh`

- [ ] 保留 orchestrator 单实例 PID 守卫。
- [ ] 增加 `MAX_PARALLEL=${MAX_PARALLEL:-2}`。
- [ ] 增加 `CLAIMS="$ROOT/.claims"`，启动时清空；worker 用 `mkdir "$CLAIMS/$n"` 原子领单。
- [ ] worker 用 `trap` 释放 claim；`fail()` 里也释放。
- [ ] `scan_ready` 从 `head -1` 改成：查全部 ready issue，排除 `processing` / `needs-human`，按空槽位启动。
- [ ] 用 `jobs -rp | wc -l` 控制槽位；bash 5 可用 `wait -n`，本机是 bash 5.3。
- [ ] `process_one` 里删除“往 `joke.md` 追加”的整段逻辑。
- [ ] 改为把 `pr/NNN.entry.md` 复制/写成 `jokes/NNN.md`。
- [ ] `git add joke.md images` 改为 `git add jokes images`。
- [ ] 删除末尾的 `git checkout main` 和 `git pull --ff-only`。
- [ ] `git worktree add` 加 3 次重试；并发时可能撞 git 锁。
- [ ] 主循环开头只 `git fetch origin main`，不 build、不 push main。
- [ ] `--once` 要等所有后台 worker 结束再退出。

关键约束：

- worker 建 worktree 必须用 `origin/main`，不要用本地 `main`。
- 不要在 `run.sh` 里 `git reset --hard` 本地 main。
- 不要让 worker 更新或 checkout 仓库根目录的 main。

### T5. 新增 CI

文件：`.github/workflows/rebuild-joke.yml`

```yaml
name: rebuild joke index
on:
  push:
    branches: [main]
concurrency:
  group: rebuild-joke-index
  cancel-in-progress: false
jobs:
  rebuild:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - run: python3 build.py
      - run: |
          git config user.name "joke-bot"
          git config user.email "joke-bot@users.noreply.github.com"
          git add joke.md jokes
          git diff --cached --quiet && exit 0
          git commit -m "rebuild joke.md"
          git push
```

- [ ] 不加 `paths` 过滤也可以：CI 自己的提交会再触发一次，但第二次没有 diff，直接退出，不会死循环。
- [ ] `git add` 必须同时包含 `jokes`：外部 PR 直接改 `joke.md` 时，`migrate()` 会新增 `jokes/NNN.md`。
- [ ] 如果以后给 main 开“必须走 PR”，要给这个 workflow 的 token 开 bypass，或 main 只要求 status checks、不强制 PR。
- [ ] CI 只负责重建索引，不负责合并 PR。

### T6. 配图侧加固

- [ ] `prompts/draw.md` 的命令加 `--timeout 600`。
- [ ] `../comic-tools/comicgen.py`：429 改为可重试。现在 `retryable = not (400 <= err.code < 500)`，429 会被当成不可重试。
- [ ] 退避加随机抖动，避免多个 worker 同时重试。
- [ ] `MAX_PARALLEL` 保持 2，先不要到 5 以上。
- [ ] 不要通过 `launch-model.sh` 加载第二个模型副本；每个副本都会吃十几 GB 显存。

### T7. 文档

- [ ] `README.md`：贡献方式改为“新增 `jokes/NNN.md`，不要直接改 `joke.md`”。
- [ ] `README.md`：说明 `joke.md` 是生成物，由 CI 重建。
- [ ] 加 `CONTRIBUTING.md` 或 PR 模板，写清路径和格式。
- [ ] `AGENTS.md` 的目录说明补上 `jokes/`、`build.py`。
- [ ] 可选：加 PR 检查，修改 `joke.md` 直接失败，要求新增 `jokes/NNN.md`。

### T8. 验收

- [ ] 同时准备 2 个 `ready` issue，运行 `./run.sh --once`。
- [ ] 两个 PR 都成功合并，没有冲突。
- [ ] `joke.md` 同时包含两条，编号排序正确。
- [ ] 两张图片都存在，`verify.sh` 通过。
- [ ] 两条 issue 都关闭，`processing` 标签被移除。
- [ ] 中途 kill 再启动，没有重复处理；`.claims` 能自清理。
- [ ] 手动造一个“只改 `joke.md`、追加新 `## NNN`”的外部 PR，合并后 CI 能把它迁成 `jokes/NNN.md` 并重建。
- [ ] 把本地 `main` 故意停在旧 commit，工厂仍能正常从 `origin/main` 工作。

---

## 5. 关键约束与踩坑记录

1. **永远不要 force push main。** 本地 main 落后时，在旧数据上生成再强推，会把别人刚合入的段子从 `joke.md` 里“生成掉”。
2. **`build.py` 必须确定性。** 否则每轮 CI/循环都会产生一个无意义提交。
3. **本地 `main` 不是事实源。** 用 CI 后，`origin/main` 才是；本地 main 旧不旧不影响生产。想更新时 `git pull --ff-only`。
4. **外部 PR 直接改已有条目**不会被迁移；只有新增 `## NNN` 会被 `migrate()` 抽出来。文档里要要求改 `jokes/NNN.md`。
5. **两个外部 PR 都追加到 `joke.md` 仍然会冲突。** `migrate()` 只兜底单个不规范的合并，不能替代“一单一个文件”的约定。
6. **macOS 没有 `flock`。** 用 `mkdir` 原子锁或 `python3` 的 `fcntl`；本机 bash 5.3，`BASHPID`、`wait -n` 可用。
7. **`git worktree add/remove` 并发可能撞锁。** 加 3 次重试即可，不需要全局锁。
8. **claim 用 `mkdir`。** 启动时清空 `.claims`；worker 用 `trap` 释放；`mkdir` 原子性足够。
9. **不要在 `run.sh` 里同时跑本地 build 和 CI。** 二选一，否则两个写者，虽然幂等但难排查。
10. **配图服务是串行的。** `MAX_PARALLEL` 超过服务能力只会增加排队和超时，不会提高吞吐。

---

## 6. 明确不做的事

- 不上 GitHub merge queue；
- 不写发布锁 / 合并机器人；
- 不用 `merge=union`；
- 不做多阶段队列/消息队列/微服务；
- 不把配图拆成异步补图流程（除非以后真的需要）；
- 不通过加模型副本扩配图吞吐。

---

## 7. 教学备注（名词对照）

| 现象 | 经典问题 | 本方案对应 |
| --- | --- | --- |
| 多个 PR 改同一个 `joke.md` | 共享可变热点 / 写-写冲突 | 一单一个文件，消除共享 |
| 合并顺序不同结果不同 | 缺少全序 / 序列化点 | 文件并集天然无序，Git 合并即并集 |
| `jokes/` 合并 | Grow-only Set CRDT | 并集满足交换律、结合律、幂等 |
| `jokes/*.md` → `joke.md` | Event Sourcing + 读模型 | `build.py` 是 projection |
| CI 重建索引 | Single Writer | Action 是唯一写者 |
| 配图服务串行 | 不可重入临界区 / 单线程资源 | 客户端限流 + 背压 |
| 加 worker 收益有限 | Amdahl 定律 | 串行段决定吞吐上限 |
| 排队越来越长 | Little 定律 | 利用率别贴近 1，保持低并发 |
| 重复处理同一 issue | at-least-once | 幂等键 = issue 编号，原子 claim |

核心一句话：**先消除共享写入点，再谈并发；消除不了，才用单写者排队。**

---

## 8. 实施记录

### 已完成

- 基础改造提交：`dde6f3b refactor: one file per joke, CI rebuilds joke.md`
- 新增 `jokes/NNN.md`、`build.py`；历史 `joke.md` 已拆分，`build.py` 重复运行无变化。
- `verify.sh` 改为校验 `jokes/NNN.md` + `images/NNN.*`。
- `run.sh` 支持 `MAX_PARALLEL`、原子 claim、worktree 重试、push 重试；不再写 `joke.md`，不再更新本地 main。
- 新增 `.github/workflows/rebuild-joke.yml` 和 `.github/workflows/verify.yml`。
- `prompts/draw.md` 加 `--timeout 600`。
- `../comic-tools/comicgen.py`（仓库外）已改为 429 可重试，退避加随机抖动。
- 文档：`README.md`、`AGENTS.md`、`CONTRIBUTING.md`。

### 并发 4 条实测

- 测试 issue：#21、#22、#23、#24。
- PR：#25、#26、#27、#28，全部 squash 合并。
- 4 条 issue 全部关闭，`processing` 已移除。
- `origin/main` 的 `joke.md` 已包含 `## 21`–`## 24`，编号排序正确。
- `jokes/21.md`–`jokes/24.md` 和 `images/21.*`–`images/24.*` 均已入库。
- CI：4 次 `verify pr` 和 4 次 `rebuild joke index` 全部成功。

### 测试中暴露的问题

- #24 的 `git push` 遇到一次远端瞬时拒绝（`remote rejected ... (failed)`），当时 `run.sh` 没有 push 重试，走了 `needs-human`。
- 手动重试 push 成功，并用 `gh pr create/merge` 补合了 PR #28。
- 已新增 `push_branch()`：最多 3 次重试，每次间隔递增；失败后仍保留分支，便于人工恢复。

### 尚未覆盖

- 还没有在真实外部 PR 上验证“只改 `joke.md`、追加 `## NNN`”的迁移路径；`build.py` 和 CI 逻辑已具备，建议后续用一个测试 PR 验证。
- 还没有验证“中途 kill 再启动”的 claim 自清理；启动时会清空 `.claims`，逻辑上已覆盖。
- 本地 `main` 不会因为 CI 重建而自动更新；需要时执行 `git pull --ff-only`。工厂只依赖 `origin/main`。
