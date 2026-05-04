package app

import (
	"fmt"
	"net/url"
	"regexp"
	"strings"
)

type Archive struct {
	*IIIF
}

func NewArchive() *Archive {
	return &Archive{
		IIIF: NewIiifRouter(),
	}
}

func (r *Archive) GetRouterInit(sUrl string) (map[string]interface{}, error) {
	msg, err := r.Run(sUrl)
	return map[string]interface{}{
		"type": "archive",
		"url":  sUrl,
		"msg":  msg,
	}, err
}

func (r *Archive) Run(sUrl string) (msg string, err error) {
	// Example: https://archive.org/details/06054495.cn/page/n145/mode/2up
	// Translate to: https://iiif.archive.org/iiif/06054495.cn/manifest.json
	
	itemId := r.getBookId(sUrl)
	if itemId == "" {
		return "requested URL was not found.", fmt.Errorf("could not extract item ID from %s", sUrl)
	}

	manifestUrl := fmt.Sprintf("https://iiif.archive.org/iiif/%s/manifest.json", itemId)
	
	return r.IIIF.Run(manifestUrl)
}

func (r *Archive) getBookId(sUrl string) (bookId string) {
	// Pattern for archive.org/details/<ITEM_ID>
	u, err := url.Parse(sUrl)
	if err != nil {
		return ""
	}

	if strings.Contains(u.Host, "archive.org") {
		parts := strings.Split(strings.Trim(u.Path, "/"), "/")
		if len(parts) >= 2 && parts[0] == "details" {
			return parts[1]
		}
	}

	// Fallback to regex if path structure is different but identifier exists
	m := regexp.MustCompile(`archive\.org/details/([^/?#]+)`).FindStringSubmatch(sUrl)
	if m != nil {
		return m[1]
	}
	
	return ""
}
