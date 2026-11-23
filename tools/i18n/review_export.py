#!/usr/bin/env python3
"""Round 182: a review workbook for a native speaker (Robert, 2026-11-06: Chinese is the cultivation genre's home market).

  python3 tools/i18n/review_export.py [zh_CN] [out.xlsx]

Sheets:
  Read me    what to do, in English and Chinese
  Glossary   the words the whole game leans on (realms, qi, the swarm, alchemy ...): the current translation, a suggested
             standard cultivation-novel term, how many strings use the current one, and a column for the reviewer's choice
  Strings    every string, most-seen first (short menu words and glossary words, then names, then longer text), with the
             current translation and a column for a correction
Fill only the yellow columns. Then: python3 tools/i18n/review_import.py <the file> [zh_CN]
"""
import json, os, re, sys
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.worksheet.datavalidation import DataValidation

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))

# English term -> (suggested zh, why). Suggestions follow common xianxia web-novel usage; the reviewer decides.
GLOSSARY = {
    "zh_CN": [
        ("Qi", "灵气 / 真气", "ambient qi is usually 灵气; a cultivator's own refined qi 真气"),
        ("Dao", "道", ""),
        ("Insight", "悟性 / 感悟", "洞见 reads as 'analysis'; cultivation insight is usually 感悟 (an event) or 悟性 (a stat)"),
        ("Cultivation", "修为 / 修炼", "修为 = level reached, 修炼 = the act"),
        ("Cultivator", "修士", ""),
        ("Meditate", "打坐 / 修炼", "冥想 is Western meditation; sitting to cultivate is 打坐"),
        ("Meridians", "经脉", ""),
        ("Dantian", "丹田", ""),
        ("Breakthrough", "突破", ""),
        ("Tribulation", "天劫 / 雷劫", ""),
        ("Realm", "境界", ""),
        ("Body Tempering", "炼体期 / 锻体境", ""),
        ("Qi Condensation", "炼气期", "炼气期 is the usual first realm; 凝气期 is rarer"),
        ("Foundation Establishment", "筑基期", ""),
        ("Core Formation", "结丹期 / 金丹期", ""),
        ("Nascent Soul", "元婴期", "the game has 元婴 without 期 -- keep realm names consistent"),
        ("Soul Transformation", "化神期", ""),
        ("Void Refinement", "炼虚期", ""),
        ("Body Integration", "合体期", ""),
        ("Mahayana", "大乘期", ""),
        ("Tribulation Transcendence", "渡劫期", ""),
        ("Immortal Ascension", "飞升期 / 仙人境", ""),
        ("Ascension", "飞升", ""),
        ("Transcendence", "超脱", ""),
        ("Immortal", "仙人", ""),
        ("Alchemy", "炼丹", "炼金术 is Western alchemy (lead into gold); pill-making is 炼丹"),
        ("Alchemist", "炼丹师", ""),
        ("Pill", "丹药", ""),
        ("Forge", "炼器 / 锻造", "making a magic weapon is 炼器; plain smithing 锻造"),
        ("Talisman", "符箓", ""),
        ("Formation", "阵法", ""),
        ("Spirit stones", "灵石", ""),
        ("Heart demon", "心魔", ""),
        ("Sect", "宗门", ""),
        ("Elder", "长老", ""),
        ("Inheritance", "传承", ""),
        ("Hidden master", "隐世高人", ""),
        ("Bloodline", "血脉", ""),
        ("Technique", "功法", "功法 = a cultivation method; a fighting move is often 武技 / 招式"),
        ("Arts", "武技 / 神通", "the game's 'arts' are moves you use in a fight"),
        ("Legacy", "传承 / 遗泽", ""),
        ("Nanite", "纳米虫 / 纳米", ""),
        ("The swarm", "纳米群 / 虫群", "蜂群 means a swarm of BEES -- the game's swarm is nanites"),
        ("Swarm", "纳米群 / 虫群", "蜂群 means a swarm of BEES"),
        ("Cleansing", "洗髓 / 伐毛洗髓", "meridian / marrow cleansing"),
        ("Bonds", "羁绊", ""),
        ("Familiar", "灵宠", ""),
        ("Beast", "灵兽 / 妖兽", ""),
    ],
}


def load(code):
    return json.load(open(os.path.join(GAME, "data", "i18n", code + ".json"), encoding="utf8"))


def priority(en, terms):
    words = len(en.split())
    has_term = any(re.search(r"\b" + re.escape(t) + r"\b", en, re.I) for t in terms)
    if words <= 4 and has_term:
        return 1
    if words <= 4:
        return 2
    if words <= 10:
        return 3
    return 4


def main(argv):
    code = argv[0] if argv else "zh_CN"
    out = argv[1] if len(argv) > 1 else os.path.join(GAME, "tools", "i18n", "review", "%s_review.xlsx" % code)
    cat = load(code)
    gl = GLOSSARY.get(code, [])
    terms = [g[0] for g in gl]
    yellow = PatternFill("solid", fgColor="FFF4C2")
    head = Font(bold=True)
    wrap = Alignment(wrap_text=True, vertical="top")
    wb = Workbook()
    ws = wb.active
    ws.title = "Read me"
    for row in [
        ["Dungeon Crawl Elite -- translation review (%s)" % code],
        [""],
        ["Thank you for reviewing. Please fill ONLY the yellow columns."],
        ["Glossary: for each core word, write the term the whole game should use in 'Your choice' (or leave it empty if the current one is right)."],
        ["Strings: write a better translation in 'Correction' when the current one is wrong or unnatural. Leave it empty when it is fine."],
        ["Keep every %d, %s, %.0f and {name} exactly as they are -- the game fills them in. Keep \\n (line breaks)."],
        ["Rows marked priority 1 and 2 are what players see most (menu words). Long story text (priority 4) can wait."],
        [""],
        ["感谢您的审校。请只填写黄色的列。"],
        ["术语表：请在“您的选择”中写下全游戏应统一使用的词（若当前译法正确可留空）。"],
        ["字符串：若当前译文有误或不自然，请在“更正”中写下更好的译文；没问题则留空。"],
        ["请原样保留 %d、%s、%.0f 和 {name} 等占位符，以及 \\n（换行）。"],
        ["优先级 1 和 2 是玩家最常看到的（菜单用词）；长篇剧情（优先级 4）可稍后处理。"],
    ]:
        ws.append(row)
    ws.column_dimensions["A"].width = 140
    ws["A1"].font = Font(bold=True, size=14)
    # glossary
    g = wb.create_sheet("Glossary")
    g.append(["English", "Current", "Strings using current", "Suggested (cultivation usage)", "Why", "Your choice", "Note"])
    for c in g[1]:
        c.font = head
    for en, sug, why in gl:
        cur = cat.get(en, "")
        uses = sum(1 for k, v in cat.items() if cur and cur in v and re.search(r"\b" + re.escape(en) + r"\b", k, re.I)) if cur else 0
        g.append([en, cur, uses, sug, why, "", ""])
    for r in range(2, g.max_row + 1):
        g.cell(r, 6).fill = yellow
        g.cell(r, 7).fill = yellow
    for col, w in zip("ABCDEFG", [26, 16, 10, 22, 60, 18, 30]):
        g.column_dimensions[col].width = w
    g.freeze_panes = "A2"
    # strings
    s = wb.create_sheet("Strings")
    s.append(["#", "Priority", "English", "Current", "Correction", "Note"])
    for c in s[1]:
        c.font = head
    rows = sorted(cat.items(), key=lambda kv: (priority(kv[0], terms), len(kv[0]), kv[0].lower()))
    for i, (en, cur) in enumerate(rows, 1):
        s.append([i, priority(en, terms), en, cur, "", ""])
    for r in range(2, s.max_row + 1):
        s.cell(r, 5).fill = yellow
        s.cell(r, 6).fill = yellow
        s.cell(r, 3).alignment = wrap
        s.cell(r, 4).alignment = wrap
        s.cell(r, 5).alignment = wrap
    for col, w in zip("ABCDEF", [7, 8, 60, 50, 50, 24]):
        s.column_dimensions[col].width = w
    s.freeze_panes = "C2"
    s.auto_filter.ref = "A1:F%d" % s.max_row
    os.makedirs(os.path.dirname(out), exist_ok=True)
    wb.save(out)
    n = {p: sum(1 for en, _ in rows if priority(en, terms) == p) for p in (1, 2, 3, 4)}
    print("REVIEW EXPORT %s: %d glossary words, %d strings (priority 1: %d, 2: %d, 3: %d, 4: %d) -> %s" % (code, len(gl), len(rows), n[1], n[2], n[3], n[4], out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
