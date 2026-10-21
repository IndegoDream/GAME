#!/usr/bin/env python3
"""Season ladder: season windows, points, ranks, tie-break, closing a season once with titles, archive."""
import sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from store import Store
from elite_server import season_info, season_rewards, SEASON_EPOCH
passed = failed = 0


def check(n, ok, extra=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1; print("  FAIL", n, extra)


DAY = 86400.0
check("before launch is season 0", season_info(SEASON_EPOCH - 5)["season"] == 0)
check("launch moment is season 1", season_info(SEASON_EPOCH)["season"] == 1)
check("last second of season 1", season_info(SEASON_EPOCH + 56 * DAY - 1)["season"] == 1)
check("then season 2", season_info(SEASON_EPOCH + 56 * DAY)["season"] == 2)
check("ends = start of next", season_info(SEASON_EPOCH + 3 * DAY)["ends"] == SEASON_EPOCH + 56 * DAY)
check("season length is configurable", season_info(SEASON_EPOCH + 8 * DAY, days=7)["season"] == 2)

st = Store(":memory:")
st.account("a1", "a@x"); st.account("a2", "b@x"); st.account("a3", "c@x"); st.account("a4", "d@x")
cs = []
for i, nm in enumerate(["Alpha", "Bravo", "Charlie", "Delta"]):
    c, err = st.create_char("a%d" % (i + 1), nm, 0, 1, [])
    cs.append(c)
check("four characters", all(cs))
st.add_season_points(1, cs[0], 40); st.add_season_points(1, cs[1], 90); st.add_season_points(1, cs[2], 10)
st.add_season_points(1, cs[0], 20)                     # Alpha 60
st.add_season_points(1, cs[3], 0)                      # nothing scored: not on the ladder
st.add_season_points(1, cs[3], -5)
top = st.season_top(1)
check("ordered by points", [r["name"] for r in top] == ["Bravo", "Alpha", "Charlie"], str(top))
check("zero and negative points ignored", len(top) == 3)
check("my rank", st.season_me(1, cs[0]) == {"points": 60, "rank": 2})
check("no points -> rank 0", st.season_me(1, cs[3]) == {"points": 0, "rank": 0})
st.add_season_points(2, cs[3], 5)
check("seasons are separate boards", st.season_top(2)[0]["name"] == "Delta" and len(st.season_top(2)) == 1)
# tie: earlier to reach the score ranks higher
st.add_season_points(1, cs[2], 50)                     # Charlie 60, reached after Alpha
check("tie goes to who got there first", [r["name"] for r in st.season_top(1)] == ["Bravo", "Alpha", "Charlie"])

n = st.close_season(1, season_rewards(1))
check("closing rewards the ranked", n == 3, str(n))
bravo = st.char_by_id(cs[1]["char_id"]); alpha = st.char_by_id(cs[0]["char_id"]); charlie = st.char_by_id(cs[2]["char_id"])
check("champion titles", "Season 1 Champion" in bravo["titles"] and "Season 1 Podium" in bravo["titles"] and "Ladder Elite 1" in bravo["titles"])
check("second is podium, not champion", "Season 1 Podium" in alpha["titles"] and "Season 1 Champion" not in alpha["titles"])
check("veteran needs 50 points", "Season 1 Veteran" in alpha["titles"] and "Season 1 Veteran" in bravo["titles"])
check("closing again changes nothing", st.close_season(1, season_rewards(1)) == 0)
check("no duplicate titles", bravo["titles"].count("Season 1 Champion") == 1)
rows = st.db.execute("select rank,name,points from season_archive where season=1 order by rank").fetchall()
check("standings archived", [(r["rank"], r["name"], r["points"]) for r in rows] == [(1, "Bravo", 90), (2, "Alpha", 60), (3, "Charlie", 60)], str([tuple(r) for r in rows]))
fn = season_rewards(7)
check("rank 11 with 49 points earns nothing", fn(11, 49) == [])
check("rank 11 with 50 points is a veteran", fn(11, 50) == ["Season 7 Veteran"])
print("LADDER %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
