from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__
from .config import Config
from .http import build_headers, read_url_lines
from .router import route_and_download


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="bookget",
        description="bookget Python 版：数字古籍下载工具",
    )
    parser.add_argument("url", nargs="?", help="下载 URL")
    parser.add_argument("-i", "--input", dest="input_url", default="", help="下载 URL")
    parser.add_argument("-I", "--input-file", dest="input_file", default="", help="下载 URLs 文件")
    parser.add_argument("-O", "--dir", dest="directory", default="downloads", help="保存文件到目录")
    parser.add_argument("-p", "--sequence", default="", help="页面范围，如 4:434")
    parser.add_argument("-v", "--volume", default="", help="册范围，如 1:10")
    parser.add_argument("--format", default="full/full/0/default.jpg", help="IIIF 图像请求 URI")
    parser.add_argument("-U", "--user-agent", default=Config.user_agent, help="User-Agent")
    parser.add_argument("-d", "--dzi", action=argparse.BooleanOptionalAction, default=True, help="保留兼容参数；Python 版暂不做瓦片拼接")
    parser.add_argument("-C", "--cookies", default="cookie.txt", help="cookie 文件")
    parser.add_argument("-H", "--headers", default="header.txt", help="header 文件")
    parser.add_argument("-n", "--threads", type=int, default=1, help="每任务最大线程数")
    parser.add_argument("-c", "--concurrent", type=int, default=16, help="最大并发任务数")
    parser.add_argument("--quality", type=int, default=80, help="JPG 品质兼容参数")
    parser.add_argument("--ext", default=".jpg", help="指定下载扩展名")
    parser.add_argument("--retries", type=int, default=3, help="下载重试次数")
    parser.add_argument("-T", "--timeout", type=int, default=300, help="网络超时秒数")
    parser.add_argument("--sleep", type=int, default=3, help="间隔睡眠秒数")
    parser.add_argument("-m", "--downloader_mode", type=int, default=0, help="0=默认, 1=通用批量, 2=IIIF manifest")
    parser.add_argument("-V", "--version", action="store_true", help="显示版本")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.version:
        print(f"bookget-python v{__version__}")
        return 0

    config = Config(
        input_url=args.input_url or args.url or "",
        input_file=args.input_file,
        directory=Path(args.directory),
        sequence=args.sequence,
        volume=args.volume,
        format=args.format,
        user_agent=args.user_agent,
        use_dzi=args.dzi,
        cookies=args.cookies,
        headers=args.headers,
        threads=args.threads,
        concurrent=args.concurrent,
        quality=args.quality,
        ext=args.ext,
        retries=args.retries,
        timeout=args.timeout,
        sleep=args.sleep,
        downloader_mode=args.downloader_mode,
    )
    config.normalize()
    headers = build_headers(config.user_agent, config.cookies, config.headers)

    try:
        if config.input_file:
            total = 0
            for url in read_url_lines(config.input_file):
                total += route_and_download(url, config, headers)
            print(f"All downloads complete. saved {total} files.")
            return 0

        if not config.input_url:
            build_parser().print_help()
            return 2

        route_and_download(config.input_url, config, headers)
        return 0
    except KeyboardInterrupt:
        print("cancelled", file=sys.stderr)
        return 130
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
