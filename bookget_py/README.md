# bookget Python 版

这是 `bookget` 的 Python 迁移入口，目标是让“木天”App 不再依赖 Go 编译产物。

当前已完成：

- 与原 `bookget` 兼容的主要 CLI 参数。
- 直接图片/PDF URL 下载。
- `--input-file` URL 列表下载。
- IIIF Presentation API v2/v3 manifest 解析下载。
- `[PAGE]`、`[VOL]`、`[AB]`/`[ab]` 模板批量下载。
- Cookie/Header 文件读取。
- 并发下载、重试、超时、间隔。
- 站点域名路由表骨架。

当前未完成：

- Go 版中 50+ 站点的所有定制 HTML/API 解析逻辑尚未逐站点等价迁移。
- DeepZoom/瓦片拼接尚未实现；IIIF 先使用普通图像请求。
- 需要登录、人机验证、共享内存交互的站点仍需要后续单独迁移。

运行：

```bash
./bin/bookget --help
./bin/bookget --input https://example.com/image.jpg --dir downloads
./bin/bookget --input https://example.org/manifest.json --downloader_mode 2 --dir downloads
```


## 结果、重试与目录

每个来源 URL 在输出目录下建立稳定的 `book-来源摘要/` 子目录。编号文件带有隐藏的 `.bookget/文件名.json` 校验记录（来源、大小、SHA-256）；重试校验后跳过已完成文件，不覆盖无来源记录的旧文件。不同来源不会共用 `0001.jpg/pdf`。

`--result-file result.json` 可输出版本为 1 的结构化结果：`saved`、`skipped`、`failed`、`files`、`output_directories` 和 `errors`。全部成功或全部经校验跳过时返回 0；任意失败或范围内没有可下载内容返回 1。URL 列表会处理完全部来源并汇总失败。模板页码范围只应用一次，文件名保留册号、页码和正反面标记。

`--concurrent` 控制图片下载并发，`--retries` 和 `--timeout` 控制网络请求；`--sleep` 用于国图逐册下载间隔。`--threads`、`--quality` 和 `--dzi` 保留命令行兼容，目前不提供分段下载、转码或瓦片拼接。

开发者可执行 `./scripts/build_bookget_macos.sh` 生成含 Python 与 CA 证书的独立下载引擎；`./script/build_and_run.sh --build` 会将它装入 macOS 应用。构建依赖固定在 `scripts/requirements-packaging.txt`。
