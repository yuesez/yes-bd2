"""镜中之战: 按星期用不同的 倍数 / 场数 (Leo 2026-10-15).

Leo's two presets: 周一~周四 40 倍 1 场, 周五~周日 1 倍 40 场.  Both use
exactly the day's 40 free cocktails.  The switch happens on the game day, so
the week turns over at Monday 08:00 UTC+8, not at midnight.
"""

import unittest
from datetime import datetime, timedelta, timezone

from src.utils.game_day import GAME_TZ, game_day_weekday
from src.utils.pvp_week import (
    ENABLED_KEY,
    WEEKDAY_COUNT_KEY,
    WEEKDAY_MULTIPLIER_KEY,
    WEEKEND_COUNT_KEY,
    WEEKEND_MULTIPLIER_KEY,
    active_preset,
    preset_for_weekday,
)

# Leo's settings, as saved in the config file.
LEO_CONFIG = {
    WEEKDAY_MULTIPLIER_KEY: 40,
    WEEKDAY_COUNT_KEY: "1",
    WEEKEND_MULTIPLIER_KEY: 1,
    WEEKEND_COUNT_KEY: "40",
}


def at(year, month, day, hour, minute=0, tz=GAME_TZ):
    return datetime(year, month, day, hour, minute, tzinfo=tz)


class GameDayWeekdayTest(unittest.TestCase):
    """A game day runs 08:00 UTC+8 to 08:00 the next day."""

    def test_monday_morning_before_the_refresh_is_still_sunday(self):
        # 2026-08-03 is a Monday; 2026-08-02 is a Sunday.
        self.assertEqual(6, game_day_weekday(at(2026, 8, 3, 0, 0)))
        self.assertEqual(6, game_day_weekday(at(2026, 8, 3, 7, 59)))
        self.assertEqual(0, game_day_weekday(at(2026, 8, 3, 8, 0)))

    def test_refresh_is_read_from_utc_too(self):
        # 2026-08-03 00:00 UTC+8 == 2026-08-02 16:00 UTC: still Sunday.
        moment = datetime(2026, 8, 2, 16, 0, tzinfo=timezone.utc)
        self.assertEqual(6, game_day_weekday(moment))
        self.assertEqual(6, game_day_weekday(moment + timedelta(minutes=1)))
        self.assertEqual(0, game_day_weekday(datetime(2026, 8, 3, 0, 0, tzinfo=timezone.utc)))

    def test_a_naive_timestamp_is_read_as_the_games_own_clock(self):
        self.assertEqual(0, game_day_weekday(datetime(2026, 8, 3, 9, 0)))

    def test_a_whole_week_walks_monday_to_sunday(self):
        start = at(2026, 8, 3, 8, 0)  # Monday's game day
        weekdays = [game_day_weekday(start + timedelta(days=offset)) for offset in range(7)]
        self.assertEqual([0, 1, 2, 3, 4, 5, 6], weekdays)


class PvpWeekPresetTest(unittest.TestCase):
    """周一~周四 40 倍 1 场, 周五~周日 1 倍 40 场."""

    def test_today_uses_the_monday_to_thursday_preset(self):
        monday = at(2026, 8, 3, 9, 0)
        preset = active_preset(LEO_CONFIG, monday)
        self.assertEqual("周一~周四", preset.name)
        self.assertEqual(40, preset.multiplier)
        self.assertEqual(1, preset.count)
        self.assertEqual(40, preset.multiplier * preset.count)

    def test_thursday_night_still_uses_the_monday_to_thursday_preset(self):
        # 2026-08-06 is a Thursday; its game day ends at Friday 08:00.
        thursday_night = at(2026, 8, 7, 7, 0)
        preset = active_preset(LEO_CONFIG, thursday_night)
        self.assertEqual("周一~周四", preset.name)
        self.assertEqual((40, 1), (preset.multiplier, preset.count))

    def test_friday_uses_the_weekend_preset(self):
        friday = at(2026, 8, 7, 8, 0)
        preset = active_preset(LEO_CONFIG, friday)
        self.assertEqual("周五~周日", preset.name)
        self.assertEqual(1, preset.multiplier)
        self.assertEqual(40, preset.count)
        self.assertEqual(40, preset.multiplier * preset.count)

    def test_the_weekend_preset_covers_friday_to_sunday(self):
        for offset, expected in ((0, "周五~周日"), (1, "周五~周日"), (2, "周五~周日")):
            moment = at(2026, 8, 7, 12, 0) + timedelta(days=offset)
            self.assertEqual(expected, active_preset(LEO_CONFIG, moment).name)

    def test_sunday_night_is_still_the_weekend_preset(self):
        # Sunday 2026-08-09's game day ends at Monday 08:00.
        sunday_night = at(2026, 8, 10, 7, 30)
        preset = active_preset(LEO_CONFIG, sunday_night)
        self.assertEqual("周五~周日", preset.name)
        self.assertEqual(40, preset.count)

    def test_preset_for_weekday_maps_every_day(self):
        names = [preset_for_weekday(LEO_CONFIG, day).name for day in range(7)]
        self.assertEqual(
            ["周一~周四"] * 4 + ["周五~周日"] * 3,
            names,
        )

    def test_a_count_that_does_not_fit_is_lowered(self):
        config = {**LEO_CONFIG, WEEKDAY_COUNT_KEY: "40"}  # 40 x 40 is not free
        preset = preset_for_weekday(config, 1)
        self.assertEqual(40, preset.multiplier)
        self.assertEqual(1, preset.count)

    def test_a_bad_multiplier_falls_back_to_that_periods_default(self):
        config = {**LEO_CONFIG, WEEKDAY_MULTIPLIER_KEY: "abc"}
        self.assertEqual(1, preset_for_weekday(config, 1).multiplier)
        config = {**LEO_CONFIG, WEEKEND_MULTIPLIER_KEY: "999"}
        self.assertEqual(40, preset_for_weekday(config, 5).multiplier)

    def test_a_typed_multiplier_with_a_suffix_still_reads(self):
        config = {**LEO_CONFIG, WEEKDAY_MULTIPLIER_KEY: "40倍"}
        self.assertEqual(40, preset_for_weekday(config, 1).multiplier)

    def test_a_missing_count_falls_back_to_one_battle(self):
        config = {key: value for key, value in LEO_CONFIG.items() if key != WEEKDAY_COUNT_KEY}
        self.assertEqual(1, preset_for_weekday(config, 1).count)

    def test_the_enabled_key_is_only_a_documentation_constant_here(self):
        # The task checks ENABLED_KEY itself; the resolver is pure.
        self.assertTrue(ENABLED_KEY)


if __name__ == "__main__":
    unittest.main()
