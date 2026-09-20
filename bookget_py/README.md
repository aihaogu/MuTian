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
