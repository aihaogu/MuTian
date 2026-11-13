import Foundation

@main
struct MetadataRegressionChecks {
    static func main() {
        do { try run() }
        catch { print("FAIL: \(error)"); exit(1) }
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "MetadataChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func run() throws {
        try testNames()
        try testFolderContext()
        try testOldLibraryDecodes()
        try testRecognitionProposal()
        try testCSVRoundTrip()
        try testInvalidCSV()
        try testOnlineParsing()
        print("PASS: file-name parsing, folder context, v1.0 library decoding, recognition review, CSV round trip, online record parsing")
    }

    /// name → 书名｜卷册｜作者｜朝代｜出版社｜版本｜丛书
    static func expect(_ name: String, _ expected: String) throws {
        let p = BookNameParser.parse(name: name)
        let actual = [p.title, p.volume, p.author, p.dynasty, p.publisher, p.edition, p.series].joined(separator: "｜")
        try require(actual == expected, "\(name)\n  expected \(expected)\n  actual   \(actual)")
    }

    static func testNames() throws {
        try expect("尔雅今注-徐朝华注-南开大学出版社1987", "尔雅今注｜｜徐朝华注｜｜南开大学出版社｜1987｜")
        try expect("尔雅-管锡华译注-中华书局（三全本）2017", "尔雅｜｜管锡华译注｜｜中华书局｜三全本 2017｜")
        try expect("三国志集解-卢弼-中华书局-1982", "三国志集解｜｜卢弼｜｜中华书局｜1982｜")
        try expect("金史纪事本末.清李有棠.中华书局.1980", "金史纪事本末｜｜李有棠｜清｜中华书局｜1980｜")
        try expect("南齐书.梁萧子显.中华书局.1972", "南齐书｜｜萧子显｜梁｜中华书局｜1972｜")
        try expect("广韵-陈彭年", "广韵｜｜陈彭年｜｜｜｜")
        try expect("经传释词-王引之撰-李花蕾校点-清代学术著作丛刊", "经传释词｜｜王引之撰；李花蕾校点｜｜｜｜清代学术著作丛刊")
        try expect("词林正韵_戈载_上海古籍出版社_1981年10月第1版", "词林正韵｜｜戈载｜｜上海古籍出版社｜1981年10月第1版｜")
        try expect("续资治通鉴-宋·李焘", "续资治通鉴｜｜李焘｜宋｜｜｜")
        try expect(
            "01001.点校本二十四史精装版.史记.一.卷一至卷七.纪[汉]司马迁撰.中华书局2013",
            "史记｜第1册 卷一至卷七 纪｜司马迁撰｜汉｜中华书局｜2013｜点校本二十四史精装版"
        )
        try expect(
            "02011.点校本二十四史精装版.汉书.一.卷一至一二.纪[汉]班固撰[唐]颜师古注.中华书局2013",
            "汉书｜第1册 卷一至一二 纪｜班固撰；（唐）颜师古注｜汉｜中华书局｜2013｜点校本二十四史精装版"
        )
        try expect("01《史记》（简体字本），汉 司马迁，中华书局1999", "史记｜｜司马迁｜汉｜中华书局｜简体字本 1999｜")
        try expect("点校本《清史稿》. 第03册 . 卷九至卷一六 . 中华书局1976初版", "清史稿｜第3册 卷九至卷一六｜｜｜中华书局｜点校本 1976初版｜")
        try expect("16【新编诸子集成】墨子閒诂（全2册）.清孙诒让撰.孙启治点校.中华书局.2001",
                   "墨子閒诂｜全2册｜孙诒让撰；孙启治点校｜清｜中华书局｜2001｜新编诸子集成")
        try expect("佛教十三经02：楞严经 (赖永海) ", "楞严经｜｜赖永海｜｜｜｜佛教十三经")
        try expect("杂阿含经校释 (王建伟, 金晖, 天竺三藏求那跋陀罗) (Z-Library)", "杂阿含经校释｜｜王建伟、金晖、天竺三藏求那跋陀罗｜｜｜｜")
        try expect("两唐书地理志汇释·吴松弟·(正史地理志汇释丛刊)·安徽教育2002", "两唐书地理志汇释｜｜吴松弟｜｜安徽教育｜2002｜正史地理志汇释丛刊")
        try expect("《清史编年+第七卷（嘉庆朝）》 (《清史编年+第七卷（嘉庆朝）》)", "清史编年｜第七卷（嘉庆朝）｜｜｜｜｜")
        try expect("清人文集地理类汇编6", "清人文集地理类汇编｜第6册｜｜｜｜｜")
        try expect("卷030.阮元瑜集 阮瑀", "阮元瑜集｜卷30｜阮瑀｜｜｜｜")
        try expect("1925中华民国地图集", "1925中华民国地图集｜｜｜｜｜｜")
        try expect("从《阿含经》谈如何亲近善知识", "从《阿含经》谈如何亲近善知识｜｜｜｜｜｜")
        try expect("0022", "｜第22册｜｜｜｜｜")
        try expect("固始县志-顺治本-内阁文库藏", "固始县志｜｜｜｜｜顺治本 内阁文库藏｜")
        try require(BookNameParser.chineseNumber("一〇") == 10 && BookNameParser.chineseNumber("二十一") == 21, "Chinese numerals")
    }

    static func testFolderContext() throws {
        let root = URL(fileURLWithPath: "/书库")
        func parse(_ path: String) -> ParsedBookName {
            BookNameParser.parse(itemURL: URL(fileURLWithPath: path), root: root)
        }
        let volume = parse("/书库/集/03 总集类/全宋诗（72册）-北京大学古文献研究所编-北京大学出版社.1998/01[652].pdf")
        try require(volume.title == "全宋诗" && volume.volume == "第1册" && volume.publisher == "北京大学出版社"
            && volume.author == "北京大学古文献研究所编" && volume.edition == "1998", "Numbered volume inherits from its work folder: \(volume)")

        let member = parse("/书库/集/02 别集类/汉魏六朝百三家集-明张溥编-清光绪信述堂重刊/1-22卷 兩漢22家/卷003.董胶西集 董仲舒.djvu")
        try require(member.title == "董胶西集" && member.author == "董仲舒" && member.series == "汉魏六朝百三家集"
            && member.edition == "清光绪信述堂重刊", "Collection folder becomes the series without lending its editor: \(member)")

        let topic = parse("/书库/子/佛家/阿含经/增壹阿含经学记.doc")
        try require(topic.series.isEmpty && topic.title == "增壹阿含经学记", "A plain topic folder is not a series: \(topic)")

        let download = parse("/书库/下载/0001.pdf")
        try require(download.title.isEmpty, "A generic folder name is not a title: \(download)")
    }

    static func testOldLibraryDecodes() throws {
        let book = Book.new(title: "尔雅今注-徐朝华注-南开大学出版社1987", localPath: "/书库/尔雅今注-徐朝华注-南开大学出版社1987.pdf", fileType: .pdf, pageCount: 3)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder.muTian.encode(book)) as! [String: Any]
        for key in ["publisher", "seriesName", "volume"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder.muTian.decode(Book.self, from: JSONSerialization.data(withJSONObject: object))
        try require(decoded.publisher == nil && decoded.seriesText.isEmpty && decoded.displayTitle == book.title,
            "A v1.0 book without the new keys must still decode")

        var edited = decoded
        edited.volumeText = "第2册"
        edited.publisherText = "  "
        try require(edited.displayTitle == "\(book.title) · 第2册" && edited.publisher == nil, "Text accessors trim to nil")
    }

    static func testRecognitionProposal() throws {
        var book = Book.new(title: "金史纪事本末.清李有棠.中华书局.1980", localPath: "/书库/金史纪事本末.清李有棠.中华书局.1980.pdf", fileType: .pdf, pageCount: 1)
        book.edition = "金史纪事本末.清李有棠.中华书局.1980"   // v1.0 copied the whole name here
        book.dynasty = "金"                                   // and guessed this from the title
        book.notes = "keep"
        let parsed = BookNameParser.parse(name: book.fileName)
        guard var proposal = BookRecognition.proposal(for: book, parsed: parsed) else { throw NSError(domain: "no proposal", code: 1) }
        let byField = Dictionary(uniqueKeysWithValues: proposal.changes.map { ($0.field, $0) })
        try require(byField[.title]?.newValue == "金史纪事本末" && byField[.title]?.isAccepted == true, "Untouched title is pre-accepted")
        try require(byField[.edition]?.newValue == "1980" && byField[.edition]?.isAccepted == true, "Copied-in edition is pre-accepted")
        try require(byField[.dynasty]?.newValue == "清", "Wrong dynasty gets a proposal")

        var userEdited = book
        userEdited.title = "金史紀事本末（我改过）"
        let edited = BookRecognition.proposal(for: userEdited, parsed: parsed)!
        try require(edited.changes.first { $0.field == .title }?.isAccepted == false, "A title the user changed is not pre-accepted")

        proposal.changes.removeAll { $0.field == .dynasty }
        try require(BookRecognition.apply(proposal, to: &book) && book.title == "金史纪事本末" && book.publisherText == "中华书局"
            && book.dynasty == "金" && book.notes == "keep", "Only accepted fields change")
    }

    static func testCSVRoundTrip() throws {
        var a = Book.new(title: "史记", localPath: "/书库/史记,一.pdf", fileType: .pdf, pageCount: 1)
        a.author = "司马迁撰"
        a.notes = "第一行\n第二行"
        let b = Book.new(title: "汉书", localPath: "/书库/汉书.pdf", fileType: .pdf, pageCount: 1)
        let data = LibraryCSV.export([a, b])
        let unchanged = try LibraryCSV.proposals(from: data, books: [a, b])
        try require(unchanged.isEmpty, "Exported CSV re-imports without changes (commas and quotes survive)")

        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: "\(b.id.uuidString),汉书,", with: "\(b.id.uuidString),\"汉书\",第1册")
        let changed = try LibraryCSV.proposals(from: Data(text.utf8), books: [a, b])
        try require(changed.count == 1 && changed[0].bookID == b.id && changed[0].changes.map(\.newValue) == ["第1册"],
            "Edited cell becomes one change: \(changed)")
        try require(try LibraryCSV.parse("x,\"a\"\"b\",\"c\nd\"\r\n") == [["x", "a\"b", "c\nd"]], "CSV quoting")
    }

    static func testInvalidCSV() throws {
        let book = Book.new(title: "史记", localPath: "/书库/史记.pdf", fileType: .pdf, pageCount: 1)
        let id = book.id.uuidString
        let invalid = [
            "ID,书名\n\(id),\"未闭合",
            "ID,书名\n\(id),\"史记\"多余文字",
            "ID,书名\n\(id),史\"记",
            "ID,书名\n\(id),史记,多余列",
            "ID,书名\n\(id)",
            "ID,书名,书名\n\(id),史记,汉书",
            "ID,书名\n\(id),史记新名\n\(id),另一个名字"
        ]
        for csv in invalid {
            var rejected = false
            do { _ = try LibraryCSV.proposals(from: Data(csv.utf8), books: [book]) }
            catch { rejected = true }
            try require(rejected, "Malformed or ambiguous CSV must be rejected: \(csv)")
        }
    }

    static func testOnlineParsing() throws {
        let json = #"{"@graph":[{"items":[{"title":"爾雅今注","@id":"https://ci.nii.ac.jp/ncid/BA3128143X","dc:creator":"(清)徐朝華注","dc:publisher":["南開大学出版社"],"prism:publicationDate":"1994","dcterms:isPartOf":[{"@id":"x","dc:title":"南開辞書"}]}]}]}"#
        let records = try OnlineBookLookup.parse(Data(json.utf8))
        try require(records.count == 1 && records[0].title == "尔雅今注" && records[0].publisher == "南开大学出版社"
            && records[0].series == "南开辞书" && records[0].dynasty == "清" && records[0].author == "徐朝华注",
            "CiNii record is simplified and split: \(records)")
        try require(OnlineBookLookup.cleanSeries("啸园丛书 / [(清)葛元煦辑], 第6函") == "啸园丛书", "Series statement is trimmed to its name")
        try require(OnlineBookLookup.searchableAuthor("（清）王引之撰；李花蕾校点") == "王引之", "Search uses the first author's bare name")
    }
}
