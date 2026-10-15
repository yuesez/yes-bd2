import os
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from src.ui.shell import config_form
from src.ui.shell.pvp_panel import PvpPanel, max_count
from src.utils.pvp_week import (
    ENABLED_KEY,
    WEEKDAY_COUNT_KEY,
    WEEKDAY_MULTIPLIER_KEY,
    WEEKEND_COUNT_KEY,
    WEEKEND_MULTIPLIER_KEY,
)

WEEK_DEFAULTS = {
    ENABLED_KEY: "关闭",
    WEEKDAY_MULTIPLIER_KEY: 40,
    WEEKDAY_COUNT_KEY: "1",
    WEEKEND_MULTIPLIER_KEY: 1,
    WEEKEND_COUNT_KEY: "40",
}


class _Config(dict):
    def get_default(self, key):
        return {"竞技场战斗倍数": 40, "战斗场数": "1", **WEEK_DEFAULTS}.get(key)


class _Task:
    def __init__(self, multiplier=40, count="1", **week):
        self.config = _Config(
            {
                "竞技场战斗倍数": multiplier,
                "战斗场数": count,
                "舞台移动方式": "鼠标",
                **WEEK_DEFAULTS,
                **week,
            }
        )
        self.default_config = dict(self.config)
        self.config_type = {}
        self.config_description = {}


class PVPTask(_Task):
    """Same class name as the real task, so ConfigForm picks its panel."""


class PvpPanelTest(unittest.TestCase):
    """Leo 2026-10-14: 倍数 × 场数 never over 40 free cocktails."""

    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def test_max_count_is_40_over_multiplier(self):
        self.assertEqual([max_count(m) for m in (1, 10, 13, 20, 40)], [40, 4, 3, 2, 1])

    def test_bigger_multiplier_lowers_the_count(self):
        task = _Task(5, "8")
        panel = PvpPanel(task)
        panel.multiplier.picked.emit(10)
        self.assertEqual(task.config, {**task.config, "竞技场战斗倍数": 10, "战斗场数": "4"})
        panel.multiplier.picked.emit(99)
        self.assertEqual((task.config["竞技场战斗倍数"], task.config["战斗场数"]), (40, "1"))
        panel.multiplier.picked.emit(0)
        self.assertEqual(task.config["竞技场战斗倍数"], 1)

    def test_typed_count_is_kept_within_the_limit(self):
        task = _Task(10, "3")
        panel = PvpPanel(task)
        panel.count.edit.setText("6")
        panel.count.edit.editingFinished.emit()
        self.assertEqual(task.config["战斗场数"], "4")
        self.assertEqual(panel.count.edit.text(), "4")
        panel.count.edit.setText("")
        panel.count.edit.editingFinished.emit()
        self.assertEqual((task.config["战斗场数"], panel.count.edit.text()), ("4", "4"))

    def test_steppers_stop_at_the_ends(self):
        panel = PvpPanel(_Task(40, "1"))
        self.assertFalse(panel.multiplier.plus.isEnabled())
        self.assertFalse(panel.count.plus.isEnabled())
        self.assertFalse(panel.count.minus.isEnabled())
        self.assertEqual(panel.cups_text.text(), "40 / 40 杯")

    def test_max_stays_max_and_follows_the_multiplier(self):
        task = _Task(10, "2")
        panel = PvpPanel(task)
        panel.max_button.click()
        self.assertEqual(task.config["战斗场数"], "MAX")
        panel.multiplier.picked.emit(20)
        self.assertEqual(task.config["战斗场数"], "MAX")
        self.assertEqual(panel.count.edit.text(), "2")
        panel.count.picked.emit(1)  # picking a number turns MAX off
        self.assertEqual(task.config["战斗场数"], "1")
        self.assertFalse(panel.max_button.isChecked())

    def test_saved_values_keep_their_types(self):
        task = _Task(10, "3")
        panel = PvpPanel(task)
        panel.multiplier.plus.click()
        panel.count.minus.click()
        self.assertIsInstance(task.config["竞技场战斗倍数"], int)
        self.assertIsInstance(task.config["战斗场数"], str)

    def test_task_settings_form_shows_the_panel_once(self):
        form = config_form.ConfigForm(PVPTask(), skip=("启用",))
        self.assertEqual(len(form.findChildren(PvpPanel)), 1)
        self.assertNotIn("竞技场战斗倍数", form._rows)
        self.assertNotIn("战斗场数", form._rows)
        self.assertIn("舞台移动方式", form._rows)
        form.task.config["竞技场战斗倍数"] = 20
        form.reset()
        self.assertEqual(form.findChild(PvpPanel).multiplier.edit.text(), "40")

    def test_the_form_leaves_the_week_rows_to_the_panel(self):
        form = config_form.ConfigForm(PVPTask(), skip=("启用",))
        for key in (ENABLED_KEY, WEEKDAY_MULTIPLIER_KEY, WEEKDAY_COUNT_KEY,
                    WEEKEND_MULTIPLIER_KEY, WEEKEND_COUNT_KEY):
            self.assertNotIn(key, form._rows)


class PvpWeekPanelTest(unittest.TestCase):
    """Leo 2026-10-15: 按星期切换倍率 周一~周四 40 倍 1 场 / 周五~周日 1 倍 40 场."""

    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def test_switch_writes_the_key_and_shows_both_periods(self):
        task = _Task()
        panel = PvpPanel(task)
        self.assertEqual(task.config[ENABLED_KEY], "关闭")
        panel.week_button.click()
        self.assertEqual(task.config[ENABLED_KEY], "开")
        self.assertTrue(panel.week_button.isChecked())
        # Each period shows its own pair; Leo's presets use the whole 40 cups.
        self.assertEqual(panel.weekday_multiplier.edit.text(), "40")
        self.assertEqual(panel.weekday_count.edit.text(), "1")
        self.assertEqual(panel.weekend_multiplier.edit.text(), "1")
        self.assertEqual(panel.weekend_count.edit.text(), "40")
        self.assertEqual(panel.cups_text.text(), "40 / 40 杯")

    def test_the_base_pair_dims_out_while_the_week_is_on(self):
        panel = PvpPanel(_Task())
        self.assertTrue(panel.multiplier.isEnabled())
        panel.week_button.click()
        self.assertFalse(panel.multiplier.isEnabled())
        self.assertFalse(panel.count.isEnabled())
        panel.week_button.click()
        self.assertTrue(panel.multiplier.isEnabled())

    def test_a_bigger_period_multiplier_lowers_its_own_count(self):
        task = _Task()
        panel = PvpPanel(task)
        panel.week_button.click()
        panel.weekday_count.picked.emit(4)  # 40 倍 4 场 would need 160 cups
        self.assertEqual(task.config[WEEKDAY_COUNT_KEY], "1")
        panel.weekday_multiplier.picked.emit(10)
        panel.weekday_count.picked.emit(4)
        self.assertEqual((task.config[WEEKDAY_MULTIPLIER_KEY], task.config[WEEKDAY_COUNT_KEY]),
                         (10, "4"))
        panel.weekday_multiplier.picked.emit(20)  # 20 x 4 does not fit: lower to 2
        self.assertEqual((task.config[WEEKDAY_MULTIPLIER_KEY], task.config[WEEKDAY_COUNT_KEY]),
                         (20, "2"))
        # The other period is untouched.
        self.assertEqual(task.config[WEEKEND_MULTIPLIER_KEY], 1)
        self.assertEqual(task.config[WEEKEND_COUNT_KEY], "40")

    def test_a_period_count_stops_at_forty_over_its_multiplier(self):
        task = _Task()
        panel = PvpPanel(task)
        panel.week_button.click()
        panel.weekend_count.picked.emit(40)
        self.assertEqual(task.config[WEEKEND_COUNT_KEY], "40")
        panel.weekend_multiplier.picked.emit(40)
        self.assertEqual(task.config[WEEKEND_COUNT_KEY], "1")

    def test_saved_periods_keep_their_types(self):
        task = _Task()
        panel = PvpPanel(task)
        panel.week_button.click()
        panel.weekday_multiplier.picked.emit(10)
        panel.weekday_count.picked.emit(4)
        self.assertIsInstance(task.config[WEEKDAY_MULTIPLIER_KEY], int)
        self.assertIsInstance(task.config[WEEKDAY_COUNT_KEY], str)
        self.assertIsInstance(task.config[WEEKEND_COUNT_KEY], str)


if __name__ == "__main__":
    unittest.main()
