"""镜中之战: 按星期用不同的 倍数 / 场数 (Leo 2026-10-15).

The game's weekly content refreshes Monday 08:00 UTC+8 (see
:mod:`src.utils.game_day`), so the split week is read on the game day, not on
the wall clock: Monday 02:00 still belongs to Sunday's game day.

Two presets, one for 周一~周四 and one for 周五~周日.  Each is a 倍数 (1~40)
plus the 场数 to fight at it, and 倍数 × 场数 stays inside the 40 free
cocktails a day (the count is lowered when the two do not fit).

With 「按星期切换」 off nothing here is used and the task keeps reading
竞技场战斗倍数 / 战斗场数, exactly as before.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from src.utils.game_day import game_day_weekday

ENABLED_KEY = "按星期切换倍率"
WEEKDAY_MULTIPLIER_KEY = "周一~周四 战斗倍数"
WEEKDAY_COUNT_KEY = "周一~周四 战斗场数"
WEEKEND_MULTIPLIER_KEY = "周五~周日 战斗倍数"
WEEKEND_COUNT_KEY = "周五~周日 战斗场数"

MULTIPLIER_LOW = 1
MULTIPLIER_HIGH = 40
COUNT_LOW = 1
COUNT_HIGH = 40

# Monday..Thursday use the first preset; Friday..Sunday the second.
WEEKDAY_DAYS = (0, 1, 2, 3)
WEEKEND_DAYS = (4, 5, 6)

WEEKDAY_PRESET_NAME = "周一~周四"
WEEKEND_PRESET_NAME = "周五~周日"

# 40 free cocktails a day, so 倍数 × 场数 cannot ask for more.
FREE_COCKTAILS = 40

ENABLED_OPTIONS = ["关闭", "开"]
COUNT_OPTIONS = [str(count) for count in range(COUNT_LOW, COUNT_HIGH + 1)]
MULTIPLIER_OPTIONS = [str(value) for value in (1, 2, 4, 5, 8, 10, 20, 40)]


@dataclass(frozen=True)
class PvpWeekPreset:
    """One period's 倍数 and 场数, already inside the free cocktails."""

    name: str
    weekday: int
    multiplier: int
    count: int


def _whole_int(value, default: int) -> int:
    """A config value as an int; anything unreadable falls back to ``default``."""
    try:
        return int(str(value).replace("倍", "").strip())
    except (TypeError, ValueError):
        return default


def _clamp(value: int, low: int, high: int) -> int:
    return min(high, max(low, value))


def capped_count(multiplier: int, count: int) -> int:
    """``count`` lowered so 倍数 × 场数 fits the 40 free cocktails."""
    multiplier = _clamp(multiplier, MULTIPLIER_LOW, MULTIPLIER_HIGH)
    return _clamp(count, COUNT_LOW, min(COUNT_HIGH, FREE_COCKTAILS // multiplier))


def preset_for_weekday(config, weekday: int) -> PvpWeekPreset:
    """The preset a given game-day weekday uses (0 = Monday)."""
    weekend = weekday in WEEKEND_DAYS
    name = WEEKEND_PRESET_NAME if weekend else WEEKDAY_PRESET_NAME
    multiplier_key = WEEKEND_MULTIPLIER_KEY if weekend else WEEKDAY_MULTIPLIER_KEY
    count_key = WEEKEND_COUNT_KEY if weekend else WEEKDAY_COUNT_KEY
    fallback_multiplier = FREE_COCKTAILS if weekend else MULTIPLIER_LOW
    multiplier = _clamp(
        _whole_int(config.get(multiplier_key), fallback_multiplier),
        MULTIPLIER_LOW,
        MULTIPLIER_HIGH,
    )
    count = capped_count(multiplier, _whole_int(config.get(count_key), COUNT_LOW))
    return PvpWeekPreset(name=name, weekday=weekday, multiplier=multiplier, count=count)


def active_preset(config, now: datetime | None = None) -> PvpWeekPreset:
    """Today's preset, read on the game day (Monday 08:00 UTC+8 boundary)."""
    return preset_for_weekday(config, game_day_weekday(now))
