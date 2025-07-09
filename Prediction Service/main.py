from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, conlist, confloat
import numpy as np

app = FastAPI(title="Boom Trend Detector")

class TrendRequest(BaseModel):
    daily_counts: conlist(int, min_items=7, max_items=7)
    sensitivity: confloat(gt=0) = 1.0

def is_boom_trend(daily_counts, sensitivity=1.0):
    """
    Определяет, является ли временной ряд трендом "бум" на основе статистических правил.
    """
    days = daily_counts
    last_day = days[-1]
    max_prev = max(days[:-1])
    mean_val = np.mean(days)
    std_dev = np.std(days)
    growth_rate_1day = last_day / days[-2] if days[-2] > 0 else 1
    growth_rate_3day = last_day / np.mean(days[-4:-1]) if np.mean(days[-4:-1]) > 0 else 1

    conditions = {
        'sharp_jump': last_day > (2.5 * max_prev * sensitivity),
        'statistical_outlier': last_day > (mean_val + 2.5 * std_dev) * sensitivity,
        'high_growth': growth_rate_1day > 1.8 and last_day > 30,
        'sustained_growth': (growth_rate_3day > 1.6) and (days[-1] > days[-2] > days[-3]),
        'absolute_threshold': last_day > 50
    }

    score = 0
    if conditions['sharp_jump']:        score += 3
    if conditions['statistical_outlier']: score += 2
    if conditions['high_growth']:       score += 2
    if conditions['sustained_growth']:  score += 1
    if conditions['absolute_threshold']: score += 1

    threshold = 4 if sensitivity < 0.8 else 3 if sensitivity < 1.2 else 2
    return 1 if score >= threshold else 0

@app.post("/detect")
def detect_trend(req: TrendRequest):
    try:
        result = is_boom_trend(req.daily_counts, req.sensitivity)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"is_boom": bool(result)}
