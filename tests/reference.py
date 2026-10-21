# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Independent Python reference of the Displacement Order Blocks engine (mql5/.../DzEngine.mqh), bar by bar.

Everything at bar i is decided from bars <= i; the last bar of the arrays is the forming bar and is never used. The
rules are the ones in the DzEngine.mqh header (d = +1 demand, -1 supply):
  ATR      Wilder (RMA) of the true range, seeded with the SMA of the first `atr` values (summed in order, as MQL5);
           the impulse test of bar i uses the ATR after bar i-1.
  swing    left `swing` bars strictly lower highs (higher lows), right `swing` bars not above (not below); known at
           p + swing; a new swing replaces the previous one of its side.
  break    the first close beyond the newest swing; it uses the swing up whether or not a zone is made.
  impulse  range >= disp_mult x ATR, body >= body_pct % of the range (within 1e-9 x range, for exact decimal ties),
           closing in the break's direction.
  base     base_mode 0: nearest candle of the other colour among the `search` bars before the break bar; base_mode 1: from
           the lowest low (demand; supply: highest high, latest bar on a tie) of those bars back, the nearest candle of the
           other colour.
  zone     mode 0 full candle, 1 body, 2 mixed.
  states   per bar for every live zone made before it: broken (checked first), then tested / retested.
  cap      max_live live zones per side (0 = off): the oldest live one of that side is dropped (state 3).
"""
import numpy as np

FRESH, TESTED, BROKEN, DROPPED = 0, 1, 2, 3
KEYS = ["dem_top", "dem_bot", "sup_top", "sup_bot", "break_up", "break_dn", "tested", "retests", "broken",
        "live_dem", "live_sup", "dem_base", "sup_base"]
DEFAULTS = dict(swing=3, atr=14, search=12, zone_mode=0, test_mode=0, break_mode=0, max_live=12, base_mode=0,
                disp_mult=1.0, body_pct=55.0)


def dz_zones(t, o, h, l, c, on_bar=None, **kw):
    """-> (buffers, zones, breaks, live zones, ATR after the last closed bar). on_bar(i, zones) runs after each bar."""
    p = {**DEFAULTS, **kw}
    n = len(c)
    out = {k: np.full(n, np.nan) for k in KEYS}
    zones, breaks, live = [], [], []
    sw = [dict(i=-1, p=0.0, broken=True), dict(i=-1, p=0.0, broken=True)]
    active = [0, 0]
    atr, atr_sum = None, 0.0
    A, S = p["atr"], p["swing"]

    def reaches(z, hi, lo):
        tol = abs(z["mid"]) * 1e-10
        m = p["test_mode"]
        if z["dir"] > 0:
            return lo <= z["top"] if m == 0 else (lo <= z["mid"] + tol if m == 1 else lo <= z["bot"])
        return hi >= z["bot"] if m == 0 else (hi >= z["mid"] - tol if m == 1 else hi >= z["top"])

    def breaks_zone(z, hi, lo, cl):
        if z["dir"] > 0:
            return cl < z["bot"] if p["break_mode"] == 0 else lo < z["bot"]
        return cl > z["top"] if p["break_mode"] == 0 else hi > z["top"]

    def is_swing(q, side):
        for k in range(1, S + 1):
            if side > 0 and (h[q - k] >= h[q] or h[q + k] > h[q]):
                return False
            if side < 0 and (l[q - k] <= l[q] or l[q + k] < l[q]):
                return False
        return True

    for i in range(n - 1):
        prev = atr
        tr = h[i] - l[i] if i == 0 else max(h[i] - l[i], max(abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1])))
        if i < A - 1:
            atr_sum += tr
        elif i == A - 1:
            atr_sum += tr
            atr = atr_sum / A
        else:
            atr = (atr * (A - 1) + tr) / A
        if prev is not None and prev > 0:
            n_test = n_re = n_brk = 0
            keep = []
            for z in live:
                reach = reaches(z, h[i], l[i])
                if breaks_zone(z, h[i], l[i], c[i]):
                    z["state"], z["end"] = BROKEN, i
                    n_brk += 1
                    active[0 if z["dir"] > 0 else 1] -= 1
                    continue
                if reach:
                    if z["state"] == FRESH:
                        z["state"], z["retests"] = TESTED, 1
                        n_test += 1
                    elif not z["inside"]:
                        z["retests"] += 1
                        n_re += 1
                z["inside"] = reach
                keep.append(z)
            live = keep
            out["tested"][i], out["retests"][i], out["broken"][i] = n_test, n_re, n_brk
            for d in (1, -1):
                s = 0 if d > 0 else 1
                if sw[s]["broken"] or c[i] * d <= sw[s]["p"] * d:
                    continue
                sw[s]["broken"] = True
                out["break_up" if d > 0 else "break_dn"][i] = sw[s]["p"]
                rng, body = h[i] - l[i], abs(c[i] - o[i])
                impulse = rng > 0 and rng >= p["disp_mult"] * prev and body >= p["body_pct"] / 100.0 * rng - rng * 1e-9 \
                    and (c[i] - o[i]) * d > 0
                base, lo_j, from_j = -1, max(0, i - p["search"]), i - 1
                if impulse and p["base_mode"] == 1:
                    for j in range(i - 2, lo_j - 1, -1):     # the move's start: the lowest low (highest high), latest on a tie
                        if (l[j] < l[from_j]) if d > 0 else (h[j] > h[from_j]):
                            from_j = j
                if impulse:
                    for j in range(from_j, lo_j - 1, -1):
                        if (c[j] - o[j]) * d < 0:
                            base = j
                            break
                zi = -1
                if base >= 0:
                    bt, bb = max(o[base], c[base]), min(o[base], c[base])
                    zm = p["zone_mode"]
                    top = bt if zm == 1 else (bt if zm == 2 and d > 0 else h[base])
                    bot = bb if zm == 1 else (bb if zm == 2 and d < 0 else l[base])
                    if top - bot > 0:
                        z = dict(dir=d, top=top, bot=bot, mid=(top + bot) / 2.0, t0=base, born=i, state=FRESH,
                                 end=-1, retests=0, inside=False)
                        zi = len(zones)
                        zones.append(z)
                        live.append(z)
                        side = 0 if d > 0 else 1
                        active[side] += 1
                        if p["max_live"] > 0 and active[side] > p["max_live"]:
                            for k, y in enumerate(live):
                                if (0 if y["dir"] > 0 else 1) == side:
                                    y["state"], y["end"] = DROPPED, i
                                    del live[k]
                                    active[side] -= 1
                                    break
                        out["dem_top" if d > 0 else "sup_top"][i] = top
                        out["dem_bot" if d > 0 else "sup_bot"][i] = bot
                        out["dem_base" if d > 0 else "sup_base"][i] = i - base
                breaks.append(dict(dir=d, level=sw[s]["p"], frm=sw[s]["i"], at=i, zone=zi))
            out["live_dem"][i], out["live_sup"][i] = active[0], active[1]
        q = i - S
        if q >= S:
            for side in (1, -1):
                if is_swing(q, side):
                    sw[0 if side > 0 else 1] = dict(i=q, p=h[q] if side > 0 else l[q], broken=False)
        if on_bar is not None:
            on_bar(i, zones)
    return out, zones, breaks, live, atr
