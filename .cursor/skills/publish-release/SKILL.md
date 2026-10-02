---
name: publish-release
description: >-
  Publish a Compositor GitHub Release: write release-notes/<version>.md from
  commits since the previous tag, commit it, tag v<version>, and push so the
  release workflow can attach the disk image. Use when the user asks to
  发布 release、发版、打 tag、更新说明、GitHub Release, or to rewrite the notes
  on an existing release. Do not use GitHub MCP.
---

# 发布 Compositor 的 GitHub Release

只使用 `gh` + `git`。不要用 GitHub MCP。不要打印 `GH_TOKEN` / PAT。回复用中文。

安装包由 `.github/workflows/verify.yml` 在 `v*` 标签上构建并上传。更新说明的正文来自仓库里的 `release-notes/<version>.md`，不要在工作流里写死功能列表。

## 1. 版本号

```bash
xcodebuild -project Compositor.xcodeproj -scheme Compositor -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}'
```

记为 `VERSION`，标签为 `v${VERSION}`。工作区若还有未提交的版本号改动，先停下来告诉用户。

## 2. 更新说明文件

上一版标签（排除当前）：

```bash
git tag -l 'v*' --sort=-v:refname | grep -v "^v${VERSION}$" | head -1
```

没有上一版时读 `git log --pretty=format:'%s%n%b' --no-merges`；有则：

```bash
git log "${PREV}..HEAD" --pretty=format:'%s%n%b' --no-merges
```

写成 `release-notes/${VERSION}.md`，并纳入即将打标签的那次提交。文件第一行是标题，空一行后是正文。

标题用中文破折号：

```
v{VERSION} — {一句中文摘要}
```

正文先一段话说明这一版对使用者意味着什么，再 2～5 条 `-` 列表。写用户能感知的变化：系统要求、语言、更新方式、工具行为。丢掉纯重构、测试、版本号本身。不要写文件名。

不要在这个文件里写「右键打开」之类的安装提示，也不要写页脚。工作流会在发布时附在正文后面。

## 3. 标签与推送

云端还没有 `v${VERSION}` 时：提交说明文件，在当前 HEAD 打附注标签，再推送分支和标签。

```bash
git tag -a "v${VERSION}" -m "Compositor ${VERSION}"
git push origin HEAD "v${VERSION}"
```

云端已有该标签时：不要重打，不要 `--force`。工作流会用标签里的说明文件创建 Release 并附上 DMG。

## 4. 已经发出的 Release 只改文案

用户明确要求补上或改写某一版的更新说明时，可以覆盖标题和正文，不要动附件，不要移动标签。

把 `release-notes/${VERSION}.md` 的标题、正文，加上工作流使用的同一段安装说明和页脚，传给：

```bash
gh release edit "v${VERSION}" --title "..." --notes "..."
```

安装说明与页脚必须是：

```
在较新的 macOS 上打开前，系统会询问。请右键点 Compositor，选择「打开」，或到「系统设置 → 隐私与安全性」里允许这一次。替换「应用程序」里的副本即可，已有项目不会被改动。

---

<sub><em>Automatically published by the <code>publish-release</code> skill.</em></sub>
```

页脚这两行保持英文，不要翻译。成功后把 Release 的 URL 发给用户。
