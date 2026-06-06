// wanfang-search.js
// Extract visible journal-paper candidates from Wanfang search result pages.
(function () {
    function clean(text) {
        return (text || '').replace(/\s+/g, ' ').trim();
    }

    function absoluteURL(href) {
        if (!href) return '';
        try { return new URL(href, location.href).href; } catch (_) { return href; }
    }

    var commonChineseSurnames = [
        '赵', '钱', '孙', '李', '周', '吴', '郑', '王', '冯', '陈', '褚', '卫', '蒋', '沈', '韩', '杨',
        '朱', '秦', '尤', '许', '何', '吕', '施', '张', '孔', '曹', '严', '华', '金', '魏', '陶', '姜',
        '戚', '谢', '邹', '喻', '柏', '水', '窦', '章', '云', '苏', '潘', '葛', '奚', '范', '彭', '郎',
        '鲁', '韦', '昌', '马', '苗', '凤', '花', '方', '俞', '任', '袁', '柳', '鲍', '史', '唐', '费',
        '廉', '岑', '薛', '雷', '贺', '倪', '汤', '滕', '殷', '罗', '毕', '郝', '邬', '安', '常', '乐',
        '于', '时', '傅', '皮', '卞', '齐', '康', '伍', '余', '元', '卜', '顾', '孟', '平', '黄', '和',
        '穆', '萧', '尹', '姚', '邵', '湛', '汪', '祁', '毛', '禹', '狄', '米', '贝', '明', '臧', '计',
        '伏', '成', '戴', '谈', '宋', '茅', '庞', '熊', '纪', '舒', '屈', '项', '祝', '董', '梁', '杜',
        '阮', '蓝', '闵', '席', '季', '麻', '强', '贾', '路', '娄', '危', '江', '童', '颜', '郭', '梅',
        '盛', '林', '刁', '钟', '徐', '邱', '骆', '高', '夏', '蔡', '田', '胡', '凌', '霍', '虞', '万',
        '支', '柯', '昝', '管', '卢', '莫', '经', '房', '裘', '缪', '干', '解', '应', '宗', '丁', '宣',
        '邓', '郁', '单', '杭', '洪', '包', '诸', '左', '石', '崔', '吉', '龚', '程', '邢', '裴', '陆',
        '荣', '翁', '荀', '羊', '於', '惠', '甄', '曲', '家', '封', '芮', '羿', '储', '靳', '汲', '邴',
        '糜', '松', '井', '段', '富', '巫', '乌', '焦', '巴', '弓', '牧', '隗', '山', '谷', '车', '侯',
        '宓', '蓬', '全', '郗', '班', '仰', '秋', '仲', '伊', '宫', '宁', '仇', '栾', '暴', '甘', '斜',
        '厉', '戎', '祖', '武', '符', '刘', '景', '詹', '束', '龙', '叶', '幸', '司', '韶', '郜', '黎',
        '蓟', '薄', '印', '宿', '白', '怀', '蒲', '邰', '从', '鄂', '索', '咸', '籍', '赖', '卓', '蔺',
        '屠', '蒙', '池', '乔', '阴', '胥', '能', '苍', '双', '闻', '莘', '党', '翟', '谭', '贡', '劳',
        '逄', '姬', '申', '扶', '堵', '冉', '宰', '郦', '雍', '郤', '璩', '桑', '桂', '濮', '牛', '寿',
        '通', '边', '扈', '燕', '冀', '郏', '浦', '尚', '农', '温', '别', '庄', '晏', '柴', '瞿', '阎',
        '充', '慕', '连', '茹', '习', '宦', '艾', '鱼', '容', '向', '古', '易', '慎', '戈', '廖', '庾',
        '终', '暨', '居', '衡', '步', '都', '耿', '满', '弘', '匡', '国', '文', '寇', '广', '禄', '阙',
        '东', '欧', '殳', '沃', '利', '蔚', '越', '夔', '隆', '师', '巩', '厍', '聂', '晁', '勾', '敖',
        '融', '冷', '訾', '辛', '阚', '那', '简', '饶', '空', '曾', '毋', '沙', '乜', '养', '鞠', '须',
        '丰', '巢', '关', '蒯', '相', '查', '后', '荆', '红', '游', '竺', '权', '逯', '盖', '益', '桓',
        '公', '角'
    ];
    var compoundChineseSurnames = [
        '欧阳', '太史', '端木', '上官', '司马', '东方', '独孤', '南宫', '万俟', '闻人', '夏侯', '诸葛',
        '尉迟', '公羊', '赫连', '澹台', '皇甫', '宗政', '濮阳', '公冶', '太叔', '申屠', '公孙', '慕容',
        '仲孙', '钟离', '长孙', '宇文', '司徒', '鲜于', '司空', '闾丘', '子车', '亓官', '司寇', '巫马',
        '公西', '颛孙', '壤驷', '公良', '漆雕', '乐正', '宰父', '谷梁', '拓跋', '夹谷', '轩辕', '令狐',
        '段干', '百里', '呼延', '东郭', '南门', '羊舌', '微生', '公户', '公玉', '公仪', '梁丘', '公仲',
        '公上', '公门', '公山', '公坚', '左丘', '公伯', '西门', '公祖', '第五', '公乘', '贯丘', '公皙',
        '南荣', '东里', '东宫', '仲长', '子书', '子桑', '即墨', '达奚', '褚师'
    ];

    function chineseSurnameLength(chars, index) {
        if (index + 1 < chars.length && compoundChineseSurnames.indexOf(chars[index] + chars[index + 1]) >= 0) return 2;
        return commonChineseSurnames.indexOf(chars[index]) >= 0 ? 1 : 0;
    }

    function segmentChineseAuthorRun(chars, index, memo) {
        if (index === chars.length) return [];
        if (memo[index]) return memo[index];
        var surnameLength = chineseSurnameLength(chars, index);
        if (!surnameLength) return null;
        var best = null;
        [1, 2].forEach(function (givenLength) {
            var end = index + surnameLength + givenLength;
            if (end > chars.length) return;
            var rest = segmentChineseAuthorRun(chars, end, memo);
            if (!rest) return;
            var name = chars.slice(index, end).join('');
            var candidate = [name].concat(rest);
            if (!best || candidate.length > best.length) best = candidate;
        });
        memo[index] = best;
        return best;
    }

    function splitChineseAuthorRun(name) {
        name = clean(name);
        if (!/^[\u4e00-\u9fff]{4,}$/.test(name)) return [name];
        var chars = Array.from(name);
        var segmented = segmentChineseAuthorRun(chars, 0, {});
        return segmented && segmented.length > 1 ? segmented : [name];
    }

    function isBlocked() {
        var marker = clean([document.title, location.href, document.body && document.body.innerText].join(' ')).toLowerCase();
        return marker.indexOf('fault filter abort') >= 0
            || marker.indexOf('安全验证') >= 0
            || marker.indexOf('访问异常') >= 0
            || marker.indexOf('captcha') >= 0;
    }

    function parseCandidate(container) {
        var text = clean(container.innerText || container.textContent || '');
        if (!text || text.indexOf('[期刊论文]') < 0) return null;

        var title = '';
        var titleMatch = text.match(/(?:^|\s)(?:\d+\.)\s*(.*?)\s*\[期刊论文\]/);
        if (titleMatch) {
            title = clean(titleMatch[1]);
        }
        if (!title) {
            var beforeType = text.split('[期刊论文]')[0];
            title = clean(beforeType.replace(/^\d+\.\s*/, ''));
        }
        if (!title || title.length < 6) return null;

        var journal = null;
        var journalMatch = text.match(/《([^》]+)》/);
        if (journalMatch) journal = clean(journalMatch[1]);

        var year = null;
        var yearMatch = text.match(/((?:19|20)\d{2})年/);
        if (yearMatch) year = parseInt(yearMatch[1], 10);

        var authors = [];
        var authorsMatch = text.match(/\[期刊论文\]\s*([\s\S]{0,120}?)(?:[-－]\s*)?《/);
        if (authorsMatch) {
            authors = clean(authorsMatch[1])
                .replace(/等$/, '')
                .split(/[,\s，、;；]+/)
                .map(clean)
                .filter(function (name) { return name && name.length <= 20 && name !== '-'; })
                .reduce(function (items, name) {
                    return items.concat(splitChineseAuthorRun(name));
                }, []);
        }

        var abstract = null;
        var abstractMatch = text.match(/摘要[:：]\s*([\s\S]*?)(?:关键词|在线阅读|下载|引用|收藏|被引[:：]|$)/);
        if (abstractMatch) abstract = clean(abstractMatch[1]);

        var detailURL = '';
        var anchors = Array.prototype.slice.call(container.querySelectorAll('a[href]'));
        var detailAnchor = anchors.find(function (a) {
            var href = a.getAttribute('href') || '';
            var label = clean(a.innerText || a.textContent || '');
            return href.indexOf('wanfangdata.com.cn') >= 0
                && href.indexOf('/wf/detail') >= 0
                && label.indexOf('客服') < 0;
        });
        if (detailAnchor) detailURL = absoluteURL(detailAnchor.getAttribute('href'));
        if (!detailURL) detailURL = location.href;

        return {
            title: title,
            url: detailURL,
            authors: authors,
            journal: journal,
            year: year,
            abstract: abstract
        };
    }

    try {
        var results = [];
        var candidates = Array.prototype.slice.call(document.querySelectorAll('div, li, section, article'))
            .filter(function (el) {
                var text = clean(el.innerText || el.textContent || '');
                return text.indexOf('[期刊论文]') >= 0
                    && text.indexOf('摘要') >= 0
                    && text.length >= 80
                    && text.length <= 3000;
            })
            .sort(function (a, b) {
                return clean(a.innerText || a.textContent || '').length
                    - clean(b.innerText || b.textContent || '').length;
            });

        var seen = {};
        for (var i = 0; i < candidates.length && results.length < 10; i++) {
            var parsed = parseCandidate(candidates[i]);
            if (!parsed) continue;
            var key = parsed.title + '|' + (parsed.journal || '') + '|' + (parsed.year || '');
            if (seen[key]) continue;
            seen[key] = true;
            results.push(parsed);
        }

        return JSON.stringify({
            status: isBlocked() ? 'blocked' : 'ok',
            results: results,
            itemCount: candidates.length,
            pageTitle: document.title,
            pageURL: location.href
        });
    } catch (e) {
        return JSON.stringify({
            status: 'error',
            message: e.message,
            results: [],
            pageTitle: document.title,
            pageURL: location.href
        });
    }
})();
