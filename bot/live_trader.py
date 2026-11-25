#!/usr/bin/env python3
"""
FTMO live demo bot — mirrors the verified D1 strategy exactly:
  ADX(14) > 27 trend filter + RSI(14) pullback from EMA200 + 1.5xATR SL / 4xATR TP.
Runs once per invocation (meant to be triggered daily by a GitHub Actions cron,
right after the D1 candle closes). DEMO ACCOUNT ONLY. Self-imposed safety limits
well inside FTMO's real rules (5% daily / 10% total loss):
  - risk 1.0% of balance per trade (not 2.5% used in the backtest)
  - hard stop: skip trading if today's floating+realized loss already >= 3%
  - only ever one open position on the traded symbol
"""
import os, sys, json, datetime
import MetaTrader5 as mt5

LOGIN    = int(os.environ["B_LOGIN"])
PASSWORD = os.environ["B_PASSWORD"]
SERVER   = os.environ["B_SERVER"]
SYMBOL   = os.environ.get("B_SYMBOL", "")
DIAGNOSE = os.environ.get("DIAGNOSE", "0") == "1"

RISK_PERCENT     = 1.0
DAILY_LOSS_LIMIT = 3.0   # self-imposed, FTMO's real limit is 5%
ADX_TH           = 27.0
STOP_ATR         = 1.5
TARGET_ATR       = 4.0

def log(msg):
    print(f"[{datetime.datetime.utcnow().isoformat()}Z] {msg}", flush=True)

def ema(values, span):
    k = 2 / (span + 1)
    out = [values[0]]
    for v in values[1:]:
        out.append(v * k + out[-1] * (1 - k))
    return out

def rsi(closes, period=14):
    gains, losses = [0.0], [0.0]
    for i in range(1, len(closes)):
        d = closes[i] - closes[i-1]
        gains.append(max(d, 0)); losses.append(max(-d, 0))
    def sma(a, p, i):
        return sum(a[i-p+1:i+1]) / p
    out = [None] * len(closes)
    for i in range(period, len(closes)):
        g = sma(gains, period, i); l = sma(losses, period, i)
        out[i] = 100.0 if l == 0 else 100 - 100 / (1 + g / l)
    return out

def atr(highs, lows, closes, period=14):
    trs = [highs[0] - lows[0]]
    for i in range(1, len(closes)):
        tr = max(highs[i]-lows[i], abs(highs[i]-closes[i-1]), abs(lows[i]-closes[i-1]))
        trs.append(tr)
    out = [None]*len(trs)
    for i in range(period, len(trs)):
        out[i] = sum(trs[i-period+1:i+1]) / period
    return out

def adx(highs, lows, closes, period=14):
    plus_dm, minus_dm, trs = [0.0], [0.0], [highs[0]-lows[0]]
    for i in range(1, len(closes)):
        up = highs[i] - highs[i-1]
        down = lows[i-1] - lows[i]
        plus_dm.append(up if (up > down and up > 0) else 0.0)
        minus_dm.append(down if (down > up and down > 0) else 0.0)
        trs.append(max(highs[i]-lows[i], abs(highs[i]-closes[i-1]), abs(lows[i]-closes[i-1])))
    out = [None]*len(closes)
    for i in range(period, len(closes)):
        atr14 = sum(trs[i-period+1:i+1]) / period
        if atr14 == 0: continue
        pdi = 100 * (sum(plus_dm[i-period+1:i+1]) / period) / atr14
        mdi = 100 * (sum(minus_dm[i-period+1:i+1]) / period) / atr14
        dx = 100 * abs(pdi - mdi) / (pdi + mdi) if (pdi+mdi) else 0
        out[i] = dx
    # simple smoothing like the python backtest (rolling mean of dx)
    smoothed = [None]*len(out)
    vals = [v for v in out if v is not None]
    idx0 = out.index(vals[0]) if vals else None
    if idx0 is not None:
        for i in range(idx0+period, len(out)):
            window = [x for x in out[i-period+1:i+1] if x is not None]
            if len(window) == period:
                smoothed[i] = sum(window)/period
    return smoothed

def main():
    if not mt5.initialize(login=LOGIN, password=PASSWORD, server=SERVER):
        log(f"initialize() failed: {mt5.last_error()}")
        sys.exit(1)
    info = mt5.account_info()
    log(f"connected: login={info.login} balance={info.balance} equity={info.equity} server={info.server}")

    if DIAGNOSE or not SYMBOL:
        syms = mt5.symbols_get()
        candidates = [s.name for s in syms if any(k in s.name.upper() for k in ["NAS", "US100", "USTEC", "NDX", "100"])]
        log(f"symbol candidates ({len(candidates)}): {candidates[:60]}")
        mt5.shutdown()
        return

    sym_info = mt5.symbol_info(SYMBOL)
    if sym_info is None or not mt5.symbol_select(SYMBOL, True):
        log(f"symbol {SYMBOL} not available")
        mt5.shutdown(); sys.exit(1)

    rates = mt5.copy_rates_from_pos(SYMBOL, mt5.TIMEFRAME_D1, 0, 260)
    if rates is None or len(rates) < 210:
        log(f"not enough D1 history: {0 if rates is None else len(rates)} bars")
        mt5.shutdown(); sys.exit(1)

    closes = [r['close'] for r in rates]
    highs  = [r['high']  for r in rates]
    lows   = [r['low']   for r in rates]

    ema200 = ema(closes, 200)
    rsi14  = rsi(closes, 14)
    atr14  = atr(highs, lows, closes, 14)
    adx14  = adx(highs, lows, closes, 14)

    i = len(closes) - 2   # last CLOSED bar (pos 0 from copy_rates_from_pos can be the forming bar)
    prev = i - 1
    if adx14[i] is None or atr14[i] is None or rsi14[prev] is None:
        log("indicators not ready yet (insufficient history)")
        mt5.shutdown(); return

    log(f"bar={datetime.datetime.utcfromtimestamp(rates[i]['time'])} close={closes[i]:.2f} "
        f"EMA200={ema200[i]:.2f} RSI={rsi14[i]:.1f} ADX={adx14[i]:.1f} ATR={atr14[i]:.2f}")

    # --- daily loss circuit breaker ---
    today = datetime.datetime.utcnow().date()
    deals = mt5.history_deals_get(datetime.datetime.combine(today, datetime.time.min), datetime.datetime.utcnow())
    realized_today = sum(d.profit for d in deals) if deals else 0.0
    positions = mt5.positions_get(symbol=SYMBOL) or ()
    floating = sum(p.profit for p in positions)
    day_start_balance = info.balance - realized_today
    loss_pct = -(realized_today + floating) / day_start_balance * 100 if day_start_balance else 0
    log(f"today: realized={realized_today:.2f} floating={floating:.2f} loss_pct={loss_pct:.2f}% (limit {DAILY_LOSS_LIMIT}%)")
    if loss_pct >= DAILY_LOSS_LIMIT:
        log("DAILY LOSS CIRCUIT BREAKER TRIPPED — no new trades today")
        mt5.shutdown(); return

    if len(positions) > 0:
        log(f"already have {len(positions)} open position(s) on {SYMBOL} — skip")
        mt5.shutdown(); return

    if adx14[i] <= ADX_TH:
        log("ADX below threshold — no trade")
        mt5.shutdown(); return

    direction = 0
    if closes[i] > ema200[i] and rsi14[prev] < 45.0 and rsi14[i] >= 45.0:
        direction = 1
    elif closes[i] < ema200[i] and rsi14[prev] > 55.0 and rsi14[i] <= 55.0:
        direction = -1

    if direction == 0:
        log("no signal today")
        mt5.shutdown(); return

    stop_dist = atr14[i] * STOP_ATR
    target_dist = atr14[i] * TARGET_ATR
    tick = mt5.symbol_info_tick(SYMBOL)
    price = tick.ask if direction == 1 else tick.bid
    sl = price - stop_dist if direction == 1 else price + stop_dist
    tp = price + target_dist if direction == 1 else price - target_dist

    risk_money = info.balance * RISK_PERCENT / 100.0
    tick_value = sym_info.trade_tick_value
    tick_size  = sym_info.trade_tick_size
    loss_per_lot = (stop_dist / tick_size) * tick_value if tick_size else 0
    lots = max(sym_info.volume_min, round(risk_money / loss_per_lot, 2)) if loss_per_lot > 0 else sym_info.volume_min
    step = sym_info.volume_step or 0.01
    lots = max(sym_info.volume_min, round(lots / step) * step)
    lots = min(lots, sym_info.volume_max)

    req = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": SYMBOL,
        "volume": lots,
        "type": mt5.ORDER_TYPE_BUY if direction == 1 else mt5.ORDER_TYPE_SELL,
        "price": price,
        "sl": sl,
        "tp": tp,
        "deviation": 20,
        "magic": 20261125,
        "comment": "agy D1 verified - FTMO live demo",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    log(f"SENDING ORDER: {req}")
    result = mt5.order_send(req)
    log(f"order_send result: retcode={result.retcode} comment={result.comment} order={result.order}")
    mt5.shutdown()

if __name__ == "__main__":
    main()
