"""
ICT Deterministic Engine — full implementation of ICT_SPEC.md
Every discretionary ICT concept reduced to a fixed numeric rule.
No parameter is tuned at runtime; all thresholds are declared as constants
below and documented in ICT_SPEC.md.
"""
import pandas as pd
import numpy as np

# ---- fixed constants (see ICT_SPEC.md for rationale) -----------------
DISPLACEMENT_ATR_MULT = 1.5
FVG_MIN_ATR_MULT       = 0.10
OB_SL_BUFFER_ATR_MULT  = 0.10
MIN_RR                 = 2.0
MAX_RR                 = 5.0
SWING_LEFT_RIGHT       = 2          # fractal arms
KILL_ZONES_NY = [("02:00","05:00"), ("07:00","10:00"), ("13:30","16:00")]


def load_ohlc(path, tz="America/New_York"):
    df = pd.read_csv(path, index_col=0)
    df.index = pd.to_datetime(df.index, utc=True)
    df = df.rename(columns=str.title)
    df = df[["Open","High","Low","Close"]].dropna()
    df.index = df.index.tz_convert(tz)
    df.index.name = "Date"
    return df


def compute_atr(df, n=14):
    hl = df["High"] - df["Low"]
    hc = (df["High"] - df["Close"].shift()).abs()
    lc = (df["Low"] - df["Close"].shift()).abs()
    tr = pd.concat([hl, hc, lc], axis=1).max(axis=1)
    return tr.ewm(alpha=1/n, adjust=False).mean()


def compute_htf_bias(df_ltf):
    """Daily EMA50 vs EMA200 bias, resampled from LTF, reindexed forward
    (no lookahead: bias known for day D is based on D-1 close, applied to all of day D)."""
    daily = df_ltf["Close"].resample("1D").last().dropna()
    ema50 = daily.ewm(span=50, adjust=False).mean()
    ema200 = daily.ewm(span=200, adjust=False).mean()
    bias_daily = np.where(ema50 > ema200, 1, -1)
    bias_daily = pd.Series(bias_daily, index=daily.index).shift(1)  # use prior day's confirmed bias
    # map each LTF bar to its date's bias
    bias_per_bar = bias_daily.reindex(df_ltf.index.normalize(), method="ffill")
    bias_per_bar.index = df_ltf.index
    return bias_per_bar


def find_swings(df, lr=SWING_LEFT_RIGHT):
    """Confirmed fractal swing highs/lows. A swing at bar i is only KNOWN
    once bar i+lr has closed (no lookahead) -> we mark it at confirm_idx=i+lr."""
    highs = df["High"].values
    lows = df["Low"].values
    n = len(df)
    swing_high = np.zeros(n, dtype=bool)
    swing_low = np.zeros(n, dtype=bool)
    confirmed_high_at = np.full(n, -1)
    confirmed_low_at = np.full(n, -1)
    for i in range(lr, n - lr):
        window_h = highs[i-lr:i+lr+1]
        window_l = lows[i-lr:i+lr+1]
        if highs[i] == window_h.max() and np.argmax(window_h) == lr:
            swing_high[i] = True
            confirmed_high_at[i] = i + lr
        if lows[i] == window_l.min() and np.argmin(window_l) == lr:
            swing_low[i] = True
            confirmed_low_at[i] = i + lr
    out = pd.DataFrame({
        "swing_high": swing_high, "swing_low": swing_low,
        "confirm_high_idx": confirmed_high_at, "confirm_low_idx": confirmed_low_at,
    }, index=df.index)
    return out


def tag_kill_zone(idx):
    t = idx.strftime("%H:%M")
    for start, end in KILL_ZONES_NY:
        if start <= t <= end:
            return True
    return False


def run_structure_and_signals(df):
    """Main deterministic ICT state machine. Returns df with signal column
    (1=long entry trigger, -1=short entry trigger) aligned so that signal at
    bar i means: ENTER AT OPEN OF BAR i+1."""
    df = df.copy()
    df["ATR14"] = compute_atr(df)
    df["bias"] = compute_htf_bias(df)
    swings = find_swings(df)
    df = df.join(swings)
    n = len(df)

    # running known (confirmed, un-burned) swing levels
    last_swing_high_price = None
    last_swing_high_burned = False
    last_swing_low_price = None
    last_swing_low_burned = False
    trend_state = 0  # 1 bull, -1 bear, 0 unknown

    pending_ob = None   # dict: dir, zone_low, zone_high, idx
    pending_fvg = None  # dict: dir, zone_low, zone_high, idx

    signal = np.zeros(n)
    sl_arr = np.full(n, np.nan)
    tp_arr = np.full(n, np.nan)
    dbg = []

    # pre-scan confirmed swing events keyed by confirm index
    confirm_high_events = {}
    confirm_low_events = {}
    for i in range(n):
        ch = df["confirm_high_idx"].iat[i]
        cl = df["confirm_low_idx"].iat[i]
        if ch >= 0:
            confirm_high_events.setdefault(ch, []).append(i)
        if cl >= 0:
            confirm_low_events.setdefault(cl, []).append(i)

    recent_high_pivot_idx = None
    recent_low_pivot_idx = None

    sweep_state = None  # 'bull_judas' or 'bear_judas' once a liquidity sweep against bias detected, waiting CHoCH
    funnel = {"sweeps":0, "choch_after_sweep":0, "ob_or_fvg_built":0, "touched_zone":0,
              "pd_zone_ok":0, "killzone_ok":0, "rr_ok":0}

    for i in range(SWING_LEFT_RIGHT, n):
        row = df.iloc[i]
        atr = row["ATR14"]
        if pd.isna(atr) or atr == 0:
            continue

        # update confirmed swing levels (only now visible, i == confirm idx)
        if i in confirm_high_events:
            for orig in confirm_high_events[i]:
                last_swing_high_price = df["High"].iat[orig]
                last_swing_high_burned = False
                recent_high_pivot_idx = orig
        if i in confirm_low_events:
            for orig in confirm_low_events[i]:
                last_swing_low_price = df["Low"].iat[orig]
                last_swing_low_burned = False
                recent_low_pivot_idx = orig

        close = row["Close"]; high = row["High"]; low = row["Low"]; openp = row["Open"]
        bias = row["bias"]

        # ---- structure break detection (BOS/CHoCH) via CLOSE only ----
        broke_up = last_swing_high_price is not None and not last_swing_high_burned and close > last_swing_high_price
        broke_down = last_swing_low_price is not None and not last_swing_low_burned and close < last_swing_low_price

        if broke_up:
            if trend_state <= 0:
                trend_state = 1  # CHoCH to bullish
            last_swing_high_burned = True
        if broke_down:
            if trend_state >= 0:
                trend_state = -1  # CHoCH to bearish
            last_swing_low_burned = True

        # ---- liquidity sweep (strict same-bar rejection) ----
        if pd.notna(bias):
            if bias == 1 and last_swing_low_price is not None and not last_swing_low_burned:
                if low < last_swing_low_price and close > last_swing_low_price:
                    sweep_state = ("bull_judas", i)
                    funnel["sweeps"] += 1
            if bias == -1 and last_swing_high_price is not None and not last_swing_high_burned:
                if high > last_swing_high_price and close < last_swing_high_price:
                    sweep_state = ("bear_judas", i)
                    funnel["sweeps"] += 1

        # ---- after a sweep, look for CHoCH aligned with bias -> build OB/FVG ----
        if sweep_state is not None:
            kind, sweep_idx = sweep_state
            if kind == "bull_judas" and bias == 1 and broke_up and i > sweep_idx:
                funnel["choch_after_sweep"] += 1
                ob_idx = None
                for k in range(i-1, sweep_idx-1, -1):
                    if df["Close"].iat[k] < df["Open"].iat[k]:
                        ob_idx = k; break
                built = False
                if ob_idx is not None and (row["High"] - row["Low"]) >= DISPLACEMENT_ATR_MULT*atr:
                    pending_ob = {"dir":1, "lo":df["Low"].iat[ob_idx], "hi":df["High"].iat[ob_idx], "idx":ob_idx, "burned":False}
                    built = True
                if i >= 2 and df["Low"].iat[i] > df["High"].iat[i-2]:
                    gap = df["Low"].iat[i] - df["High"].iat[i-2]
                    if gap >= FVG_MIN_ATR_MULT*atr:
                        pending_fvg = {"dir":1, "lo":df["High"].iat[i-2], "hi":df["Low"].iat[i], "idx":i, "burned":False}
                        built = True
                if built:
                    funnel["ob_or_fvg_built"] += 1
                sweep_state = None
            elif kind == "bear_judas" and bias == -1 and broke_down and i > sweep_idx:
                funnel["choch_after_sweep"] += 1
                ob_idx = None
                for k in range(i-1, sweep_idx-1, -1):
                    if df["Close"].iat[k] > df["Open"].iat[k]:
                        ob_idx = k; break
                built = False
                if ob_idx is not None and (row["High"] - row["Low"]) >= DISPLACEMENT_ATR_MULT*atr:
                    pending_ob = {"dir":-1, "lo":df["Low"].iat[ob_idx], "hi":df["High"].iat[ob_idx], "idx":ob_idx, "burned":False}
                    built = True
                if i >= 2 and df["High"].iat[i] < df["Low"].iat[i-2]:
                    gap = df["Low"].iat[i-2] - df["High"].iat[i]
                    if gap >= FVG_MIN_ATR_MULT*atr:
                        pending_fvg = {"dir":-1, "lo":df["High"].iat[i], "hi":df["Low"].iat[i-2], "idx":i, "burned":False}
                        built = True
                if built:
                    funnel["ob_or_fvg_built"] += 1
                sweep_state = None

        # ---- check entry: price retraces into OB/FVG zone, in correct PD zone + kill zone ----
        zone = None
        if pending_ob is not None and not pending_ob["burned"]:
            zone = pending_ob
        elif pending_fvg is not None and not pending_fvg["burned"]:
            zone = pending_fvg

        if zone is not None and recent_high_pivot_idx is not None and recent_low_pivot_idx is not None:
            swing_hi = df["High"].iat[recent_high_pivot_idx]
            swing_lo = df["Low"].iat[recent_low_pivot_idx]
            rng = swing_hi - swing_lo
            if rng > 0:
                midpoint = swing_lo + 0.5*rng
                in_discount = close <= midpoint
                in_premium = close >= midpoint
                in_kz = tag_kill_zone(row.name)
                touched = low <= zone["hi"] and high >= zone["lo"]
                if touched:
                    funnel["touched_zone"] += 1

                if zone["dir"] == 1 and touched and in_discount and close > openp:
                    funnel["pd_zone_ok"] += 1
                    if in_kz:
                        funnel["killzone_ok"] += 1
                        sl = zone["lo"] - OB_SL_BUFFER_ATR_MULT*atr
                        risk = close - sl
                        target_liq = swing_hi  # nearest opposite unburned liquidity
                        reward = target_liq - close
                        if risk > 0 and reward/risk >= MIN_RR:
                            funnel["rr_ok"] += 1
                            tp = close + min(reward, MAX_RR*risk)
                            signal[i] = 1
                            sl_arr[i] = sl
                            tp_arr[i] = tp
                            zone["burned"] = True
                elif zone["dir"] == -1 and touched and in_premium and close < openp:
                    funnel["pd_zone_ok"] += 1
                    if in_kz:
                        funnel["killzone_ok"] += 1
                        sl = zone["hi"] + OB_SL_BUFFER_ATR_MULT*atr
                        risk = sl - close
                        target_liq = swing_lo
                        reward = close - target_liq
                        if risk > 0 and reward/risk >= MIN_RR:
                            funnel["rr_ok"] += 1
                            tp = close - min(reward, MAX_RR*risk)
                            signal[i] = -1
                            sl_arr[i] = sl
                            tp_arr[i] = tp
                            zone["burned"] = True
                else:
                    # OB/FVG invalidated if price closes fully through it against its direction
                    if zone["dir"] == 1 and close < zone["lo"]:
                        zone["burned"] = True
                    if zone["dir"] == -1 and close > zone["hi"]:
                        zone["burned"] = True

    df["signal"] = signal
    df["sig_sl"] = sl_arr
    df["sig_tp"] = tp_arr
    df.attrs["funnel"] = funnel
    return df


def backtest(df, spread_pts=1.66, slippage_pts=0.5):
    df = df.reset_index()
    trades = []
    open_trade = None
    for i in range(len(df) - 1):
        row = df.iloc[i]
        if open_trade is not None:
            dir_ = open_trade["dir"]; sl = open_trade["sl"]; tp = open_trade["tp"]
            hit_sl = row["Low"] <= sl if dir_==1 else row["High"] >= sl
            hit_tp = row["High"] >= tp if dir_==1 else row["Low"] <= tp
            if hit_sl or hit_tp:
                exit_price = sl if hit_sl else tp  # conservative: SL wins on same-bar ambiguity
                if hit_sl and hit_tp:
                    exit_price = sl
                pnl = (exit_price - open_trade["entry"]) * dir_ - spread_pts - slippage_pts
                trades.append({
                    "entry_date": open_trade["date"], "exit_date": row["Date"],
                    "dir": "BUY" if dir_==1 else "SELL",
                    "entry": open_trade["entry"], "exit": exit_price,
                    "sl": sl, "tp": tp,
                    "risk_pts": abs(open_trade["entry"]-sl),
                    "pnl_pts": pnl,
                    "r_multiple": pnl/abs(open_trade["entry"]-sl) if abs(open_trade["entry"]-sl)>0 else np.nan,
                })
                open_trade = None
        if open_trade is None and df["signal"].iat[i] != 0:
            nxt = df.iloc[i+1]
            dir_ = int(df["signal"].iat[i])
            entry = nxt["Open"] + (spread_pts/2 if dir_==1 else -spread_pts/2)
            open_trade = {"dir": dir_, "entry": entry, "sl": df["sig_sl"].iat[i],
                          "tp": df["sig_tp"].iat[i], "date": nxt["Date"]}
    return pd.DataFrame(trades)


def stats(trades, n_boot=5000, seed=42):
    if len(trades) == 0:
        return {"n_trades": 0}
    wins = trades["pnl_pts"] > 0
    gw = trades.loc[wins, "pnl_pts"].sum()
    gl = -trades.loc[~wins, "pnl_pts"].sum()
    pf = gw/gl if gl>0 else np.inf
    wr = wins.mean()
    equity = trades["pnl_pts"].cumsum()
    dd = (equity - equity.cummax()).min()

    rng = np.random.default_rng(seed)
    n = len(trades)
    boot_wr, boot_pf = [], []
    for _ in range(n_boot):
        idx = rng.integers(0,n,n)
        s = trades.iloc[idx]
        w = s["pnl_pts"]>0
        gw2 = s.loc[w,"pnl_pts"].sum(); gl2 = -s.loc[~w,"pnl_pts"].sum()
        boot_wr.append(w.mean()); boot_pf.append(gw2/gl2 if gl2>0 else np.nan)
    boot_wr=np.array(boot_wr); boot_pf=np.array(boot_pf)
    return {
        "n_trades": int(n),
        "win_rate": round(float(wr)*100,1),
        "win_rate_ci95": (round(float(np.nanpercentile(boot_wr,2.5))*100,1), round(float(np.nanpercentile(boot_wr,97.5))*100,1)),
        "profit_factor": round(float(pf),2) if np.isfinite(pf) else None,
        "pf_ci95": (round(float(np.nanpercentile(boot_pf,2.5)),2), round(float(np.nanpercentile(boot_pf,97.5)),2)),
        "total_pnl_pts": round(float(trades["pnl_pts"].sum()),1),
        "max_drawdown_pts": round(float(dd),1),
        "avg_r_multiple": round(float(trades["r_multiple"].mean()),3),
    }
