# DeGu

DeGu（得古）是一个本地优先的 macOS 古籍资料库应用，用于整理、收藏、检索、统计和阅读本地古籍资料。

项目一期重点包括：

- 扫描并导入本地古籍文件夹、PDF、图片序列、文本和元数据文件。
- 以经、史、子、集为核心建立四库分类体系。
- 管理书名、作者、朝代、版本、来源、标签、收藏状态和阅读进度。
- 按分类、来源、文件类型、整理状态和收藏状态统计本地资料库。
- 提供 PDF 和图片序列的基础阅读能力。
- 在 macOS App 中创建下载任务，并在下载完成后导入本地资料库。

## 下载功能来源

本项目的数字古籍下载功能来自 `bookget`。

`bookget` 原项目地址：

https://github.com/deweizhu/bookget

`bookget` 是一个数字古籍图书下载工具，支持多个数字图书馆、古籍平台和 IIIF 资源站点。得古不重写其下载逻辑，而是在 macOS App 中负责下载任务配置、进度展示、结果导入和本地资料库管理。

## 开发

运行 macOS App：

```sh
./script/build_and_run.sh
```

项目结构：

- `DeGu/`：macOS SwiftUI App 源码。
- `bookget/`：数字古籍下载引擎源码，来源于 `deweizhu/bookget`。
- `bookget_py/`：Python 版本下载能力实验实现。
- `scripts/`、`script/`：构建和运行脚本。
