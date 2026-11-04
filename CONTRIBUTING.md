# 贡献指南

## 提段子灵感

在 Issues 里点 **New issue**，选「提一个段子灵感」，写一句话就行。

## 提 PR

- 一条段子一个文件：新增 `jokes/NNN.md`，`NNN` 用 issue 编号。
- 配图放在 `images/NNN.jpg`。
- **不要直接修改 `joke.md`**。它是生成物，PR 里改了会被 `verify pr` 拦下。
- `jokes/NNN.md` 的格式：

```markdown
## NNN

中文段子

> English version

![NNN](images/NNN.jpg)

来源：issues/NNN
灵感：[@作者](https://github.com/作者)
```

## 本机检查

```bash
./verify.sh NNN
python3 build.py
```

`build.py` 会把 `joke.md` 里手写的、还没有对应文件的 `## NNN` 迁到 `jokes/NNN.md`，然后按编号重建 `joke.md`。重复运行应该是无变化的。
