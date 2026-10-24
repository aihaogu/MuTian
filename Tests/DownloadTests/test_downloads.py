import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from bookget_py.cli import main
from bookget_py.config import Config
from bookget_py.download_identity import source_directory
from bookget_py.downloader import download_urls, expand_template
from bookget_py.http import download_file
from bookget_py.router import route_and_download
from bookget_py.nlc import download_nlc


class DownloadChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mutian-download-test-")
        self.root = Path(self.temporary.name)
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.errors = contextlib.redirect_stderr(io.StringIO())
        self.output.__enter__()
        self.errors.__enter__()

    def tearDown(self):
        self.output.__exit__(None, None, None)
        self.errors.__exit__(None, None, None)
        self.temporary.cleanup()

    def config(self, **kwargs):
        result = Config(directory=self.root, sleep=0, concurrent=1, **kwargs)
        result.normalize()
        return result

    def test_all_failed_cli_is_nonzero_with_result(self):
        report = self.root / "result.json"
        with patch("bookget_py.downloader.download_file", side_effect=RuntimeError("HTTP 404")):
            code = main(["--input", "https://example.invalid/missing.jpg", "--dir", str(self.root),
                         "--result-file", str(report), "--retries", "0"])
        data = json.loads(report.read_text())
        self.assertEqual(code, 1)
        self.assertEqual(data["failed"], 1)
        self.assertEqual(data["files"], [])

    def test_partial_failure_keeps_success_and_retries_only_failure(self):
        config = self.config()
        urls = ["https://example.invalid/one.jpg", "https://example.invalid/two.jpg"]
        with patch("bookget_py.http.get_bytes", side_effect=[b"first-page", RuntimeError("404")]):
            result = download_urls(urls, config, {})
        self.assertEqual((result.saved, result.failed), (1, 1))
        with patch("bookget_py.http.get_bytes", return_value=b"second-page") as fetch:
            result = download_urls(urls, config, {})
        self.assertTrue(result.succeeded)
        self.assertEqual((result.saved, result.skipped), (1, 1))
        self.assertEqual(fetch.call_count, 1)
        self.assertEqual(fetch.call_args.args[0], urls[1])

    def test_sources_do_not_collide(self):
        first, second = "https://example.invalid/a.jpg", "https://example.invalid/b.jpg"
        with patch("bookget_py.http.get_bytes", side_effect=[b"book-a", b"book-b"]) as fetch:
            a = route_and_download(first, self.config(), {})
            b = route_and_download(second, self.config(), {})
        self.assertEqual(fetch.call_count, 2)
        self.assertNotEqual(a.files, b.files)
        self.assertEqual(Path(a.files[0]).read_bytes(), b"book-a")
        self.assertEqual(Path(b.files[0]).read_bytes(), b"book-b")

    def test_template_range_applied_once_preserves_page_volume_side(self):
        config = self.config(sequence="4:6", volume="2:3")
        items = expand_template("https://example.invalid/[VOL]/[PAGE][AB].jpg", config)
        with patch("bookget_py.http.get_bytes", return_value=b"image"):
            result = download_urls(items, config, {})
        self.assertEqual(result.saved, 12)
        self.assertEqual({Path(f).name for f in result.files}, {
            f"{volume:04d}-{page:04d}-{side}.jpg"
            for volume in [2, 3] for page in [4, 5, 6] for side in "AB"
        })

    def test_manifest_range_still_filters(self):
        urls = [f"https://example.invalid/{n}.jpg" for n in range(1, 8)]
        with patch("bookget_py.http.get_bytes", return_value=b"image") as fetch:
            result = download_urls(urls, self.config(sequence="4:6"), {})
        self.assertEqual(result.saved, 3)
        self.assertEqual([call.args[0] for call in fetch.call_args_list], urls[3:6])

    def test_unverified_or_modified_file_is_not_skipped(self):
        target = self.root / "0001.jpg"
        target.write_bytes(b"unrelated-old-book")
        with self.assertRaisesRegex(RuntimeError, "cannot be verified"):
            download_file("https://example.invalid/a.jpg", target, {}, 1, 0)
        self.assertEqual(target.read_bytes(), b"unrelated-old-book")
        target.unlink()
        with patch("bookget_py.http.get_bytes", return_value=b"valid-page"):
            download_file("https://example.invalid/a.jpg", target, {}, 1, 0)
        target.write_bytes(b"damaged")
        with self.assertRaises(RuntimeError):
            download_file("https://example.invalid/a.jpg", target, {}, 1, 0)

    def test_empty_selection_and_invalid_range_fail(self):
        self.assertFalse(download_urls(["https://example.invalid/one.jpg"], self.config(sequence="5:8"), {}).succeeded)
        for value in ["0", "-1:3", "9:2", "bad"]:
            with self.assertRaises(ValueError):
                self.config(sequence=value)

    def test_input_file_processes_every_source_and_keeps_failures(self):
        inputs = self.root / "urls.txt"
        inputs.write_text("https://example.invalid/a.jpg\nhttps://example.invalid/b.jpg\n")
        with patch("bookget_py.http.get_bytes", side_effect=[RuntimeError("404"), b"book-b"]):
            code = main(["--input-file", str(inputs), "--dir", str(self.root), "--retries", "0"])
        self.assertEqual(code, 1)
        self.assertEqual((source_directory(self.root, "https://example.invalid/b.jpg") / "0001.jpg").read_bytes(), b"book-b")

    def test_nlc_partial_and_all_failures_are_reported(self):
        with patch("bookget_py.nlc._volume_urls", return_value=["v1", "v2"]), \
             patch("bookget_py.nlc._download_volume_pdf", side_effect=[True, RuntimeError("403")]):
            result = download_nlc("book", self.config(), {})
        self.assertEqual((result.saved, result.failed), (1, 1))
        self.assertFalse(result.succeeded)
        with patch("bookget_py.nlc._volume_urls", return_value=["v1"]), \
             patch("bookget_py.nlc._download_volume_pdf", side_effect=RuntimeError("403")):
            result = download_nlc("book", self.config(), {})
        self.assertEqual((result.saved, result.failed), (0, 1))

    def test_two_workers_same_destination_fetch_only_once(self):
        from concurrent.futures import ThreadPoolExecutor
        with patch("bookget_py.http.get_bytes", return_value=b"same-page") as fetch:
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(download_file, "https://example.invalid/a.jpg", self.root / "0001.jpg", {}, 1, 0) for _ in range(2)]
                results = [f.result() for f in futures]
        self.assertEqual(sorted(results), [False, True])
        self.assertEqual(fetch.call_count, 1)


if __name__ == "__main__":
    unittest.main()
