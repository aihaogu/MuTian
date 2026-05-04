package app

import (
	"bookget/config"
	"bookget/model/iiif"
	"bookget/pkg/chttp"
	"bookget/pkg/downloader"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"path"
	"regexp"
	"strings"
	"time"
)

type Berlin struct {
	dm     *downloader.DownloadManager
	ctx    context.Context
	cancel context.CancelFunc
	client *http.Client

	bufBuilder strings.Builder
	bufString  string
	bufBody    []byte
	canvases   []string
	urlsFile   string

	rawUrl    string
	parsedUrl *url.URL
	savePath  string
	bookId    string
}

func NewBerlin() *Berlin {
	ctx, cancel := context.WithCancel(context.Background())
	dm := downloader.NewDownloadManager(ctx, cancel, config.Conf.MaxConcurrent)

	// 创建自定义 Transport 忽略 SSL 验证
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: true,
		},
	}
	jar, _ := cookiejar.New(nil)
	return &Berlin{
		// 初始化字段
		dm:     dm,
		client: &http.Client{Timeout: config.Conf.Timeout * time.Second, Jar: jar, Transport: tr},
		ctx:    ctx,
		cancel: cancel,
	}
}

func (r *Berlin) GetRouterInit(rawUrl string) (map[string]interface{}, error) {
	r.rawUrl = rawUrl
	r.parsedUrl, _ = url.Parse(rawUrl)
	err := r.Run()
	if err != nil {
		return nil, err
	}
	return map[string]interface{}{
		"type": "",
		"url":  rawUrl,
	}, nil
}

func (r *Berlin) getBookId(sUrl string) (bookId string) {
	m := regexp.MustCompile(`PPN=([A-z0-9_-]+)`).FindStringSubmatch(sUrl)
	if m != nil {
		bookId = m[1]
	}
	return bookId
}

func (r *Berlin) Run() (err error) {
	r.bookId = r.getBookId(r.rawUrl)
	if r.bookId == "" {
		return err
	}
	r.savePath = config.Conf.Directory
	r.urlsFile = path.Join(r.savePath, "urls.txt")

	apiUrl := fmt.Sprintf("https://content.staatsbibliothek-berlin.de/dc/%s/manifest", r.bookId)
	canvases, err := r.getCanvases(apiUrl)
	if err != nil || canvases == nil {
		return err
	}
	r.do(canvases)

	err = os.WriteFile(r.urlsFile, []byte(r.bufBuilder.String()), os.ModePerm)
	if err != nil {
		return err
	}

	return nil
}

func (r *Berlin) do(canvases []string) (err error) {
	if canvases == nil {
		return errors.New("no image url")
	}

	args := []string{
		"-H", "Origin: https://" + r.parsedUrl.Hostname(),
		"-H", "Referer: https://" + r.parsedUrl.Hostname(),
		"-H", "TE: trailers",
	}
	size := len(canvases)
	// 创建下载器实例
	iiifDownloader := downloader.NewIIIFDownloader(&config.Conf)
	for i, uri := range canvases {
		if uri == "" || !config.PageRange(i, size) {
			continue
		}
		sortId := fmt.Sprintf("%04d", i+1)
		filename := sortId + config.Conf.FileExt
		dest := path.Join(r.savePath, filename)
		if FileExist(dest) {
			continue
		}
		r.bufBody, err = r.getBody(uri)
		if err != nil {
			continue
		}
		dziUrl := string(r.bufBody)
		r.bufBuilder.Write(r.bufBody)
		r.bufBuilder.WriteString("\n")

		log.Printf("Get %d/%d  %s\n", i+1, size, dziUrl)
		iiifDownloader.Dezoomify(r.ctx, dziUrl, dest, args)
	}
	return nil
}

func (r *Berlin) getCanvases(sUrl string) (canvases []string, err error) {
	bs, err := r.getBody(sUrl)
	if err != nil {
		return
	}
	var manifest = new(iiif.ManifestResponse)
	if err = json.Unmarshal(bs, manifest); err != nil {
		log.Printf("json.Unmarshal failed: %s\n", err)
		return
	}
	if len(manifest.Sequences) == 0 {
		return
	}
	size := len(manifest.Sequences[0].Canvases)
	canvases = make([]string, 0, size)
	for _, canvase := range manifest.Sequences[0].Canvases {
		for _, image := range canvase.Images {
			//https://ngcs-core.staatsbibliothek-berlin.de/dzi/PPN3303598630/PHYS_0001.dzi
			m := regexp.MustCompile("/dc/([A-z0-9]+)-([A-z0-9]+)/full").FindStringSubmatch(image.Resource.Id)
			iiiInfo := fmt.Sprintf("https://content.staatsbibliothek-berlin.de/?action=metsImage&metsFile=%s&divID=PHYS_%s&dzi=true", r.bookId, m[2])
			canvases = append(canvases, iiiInfo)
		}
	}
	return canvases, nil

}

func (r *Berlin) getBody(rawUrl string) ([]byte, error) {
	req, err := http.NewRequest("GET", rawUrl, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", config.Conf.UserAgent)
	cookies, _ := chttp.ReadCookiesFromFile(config.Conf.CookieFile)
	if cookies != "" {
		req.Header.Set("Cookie", cookies)
	}
	headers, err := chttp.ReadHeadersFromFile(config.Conf.HeaderFile)
	if err == nil {
		for key, value := range headers {
			req.Header.Set(key, value)
		}
	}
	resp, err := r.client.Do(req.WithContext(r.ctx))
	if err != nil {
		return nil, err
	}
	defer func() {
		if err := resp.Body.Close(); err != nil {
			log.Printf("close body err=%v", err)
		}
	}()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
		err = fmt.Errorf("服务器返回错误状态码: %d", resp.StatusCode)
		return nil, err
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return body, nil
}

func (r *Berlin) postBody(rawUrl string, postData interface{}) ([]byte, error) {
	//TODO implement me
	panic("implement me")
}
