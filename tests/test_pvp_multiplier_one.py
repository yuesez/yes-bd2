"""镜中之战 倍率设成 1: the 🍹 icon's stray "1" must not hide the value.

Leo 2026-10-23 (v0.2.9, 1920×1080 全屏, 桌面分身): 按星期切换 set the target to
1倍 on 周五~周日, the setting dialog opened, but every read came back 「11」 —
the cocktail icon left of the value is its own OCR box and reads as a stray
"1", so the joined text is "1" + "1倍" → "11" and ^1$ never matched.  The run
stopped with 「倍率选项第3/3次点击后设置值未回读到 1」→「未能开始战斗」.

Before 按星期, the base setting was 40倍 and the dialog was never opened (the
main popup already showed 40), so this path was never exercised.
"""

import unittest
from types import SimpleNamespace
from unittest import mock

import numpy as np

from src.tasks import PVPTask as pvp_module
from src.tasks.PVPTask import (
    PVP_MULTIPLIER_1_OPTION_SCREEN_POINT,
    PVP_MULTIPLIER_SETTING_VALUE_OCR_REFERENCE_ROI,
    PVPTask,
)

SETTING_VALUE = PVPTask._mf_roi(*PVP_MULTIPLIER_SETTING_VALUE_OCR_REFERENCE_ROI)


class _ValueScreen:
    """The setting dialog's value area, answering with fixed OCR boxes."""

    def __init__(self, labels, value_after_option=None):
        self.labels = list(labels)
        self.value_after_option = value_after_option
        self.presses = []

    def labels_for(self, _roi):
        return self.labels

    def press_screen(self, x, y):
        self.presses.append((x, y))
        if (
            self.value_after_option is not None
            and (x, y) == PVP_MULTIPLIER_1_OPTION_SCREEN_POINT
        ):
            self.labels = list(self.value_after_option)


def _task(screen, clock):
    task = object.__new__(PVPTask)
    task.config = {}
    task.infos = {}
    task.logs = []
    task.info_set = lambda key, value: task.infos.__setitem__(key, value)
    task.log_info = task.logs.append
    # A stopped clock plus a sleeping reader would spin forever in
    # `_wait_for_ocr_patterns`: let sleep move the clock on.
    task.sleep = lambda seconds: clock.__setitem__(0, clock[0] + seconds)
    frame = np.zeros((1080, 1920, 3), dtype=np.uint8)
    task.capture_frame = lambda: frame

    def boxes(_frame, name, roi=None, ocr_scale=1.0):
        return [
            SimpleNamespace(name=label, confidence=0.9, x=10, y=10, width=40, height=20)
            for label in screen.labels_for(roi)
        ]

    task._ocr_boxes = boxes
    task._click_screen_reference = lambda x, y, after_sleep=0.0: screen.press_screen(x, y)
    task._click_reference = lambda x, y, after_sleep=0.0: screen.presses.append((x, y))
    return task


class MultiplierOneTest(unittest.TestCase):
    def setUp(self):
        self.clock = [0.0]
        patcher = mock.patch.object(pvp_module, "monotonic", lambda: self.clock[0])
        patcher.start()
        self.addCleanup(patcher.stop)

    def _task(self, screen):
        return _task(screen, self.clock)

    def test_the_icon_and_the_value_are_two_boxes(self):
        # What the OCR returned on the player's frame, joined by _ocr_text.
        task = self._task(_ValueScreen(["1", "1倍"]))
        self.assertEqual("1 1倍", task._ocr_text(task.capture_frame(), name="x", roi=SETTING_VALUE))

    def test_one_times_one_is_seen_through_the_icon_noise(self):
        task = self._task(_ValueScreen(["1", "1倍"]))
        self.assertTrue(PVPTask._setting_multiplier_matches(task, 1))
        self.assertTrue(any("图标那个数字不算" in line for line in task.logs))

    def test_a_clean_one_times_read_still_matches(self):
        task = self._task(_ValueScreen(["1倍"]))
        self.assertTrue(PVPTask._setting_multiplier_matches(task, 1))
        self.assertEqual([], task.logs)

    def test_another_value_is_not_taken_for_one(self):
        task = self._task(_ValueScreen(["40倍"]))
        self.assertFalse(PVPTask._setting_multiplier_matches(task, 1))

    def test_forty_with_the_icon_still_matches_forty(self):
        task = self._task(_ValueScreen(["1", "40倍"]))
        self.assertTrue(PVPTask._setting_multiplier_matches(task, 40))

    def test_the_value_reader_gets_one_past_the_icon(self):
        task = self._task(_ValueScreen(["1", "1倍"]))
        self.assertEqual(1, PVPTask._setting_multiplier_value(task))

    def test_a_value_merged_into_one_box_is_still_read(self):
        # One box, no 倍: parse_multiplier finds nothing, the stray digit drops.
        task = self._task(_ValueScreen(["11"]))
        self.assertEqual(1, PVPTask._setting_multiplier_value(task))

    def test_the_value_reader_keeps_forty(self):
        task = self._task(_ValueScreen(["1", "40倍"]))
        self.assertEqual(40, PVPTask._setting_multiplier_value(task))

    def test_setting_one_times_ends_with_the_value_seen(self):
        # The whole step that failed on the player's run.
        screen = _ValueScreen(["1"], value_after_option=["1", "1倍"])
        task = self._task(screen)
        self.assertTrue(PVPTask._select_setting_multiplier(task, 1))
        self.assertIn(PVP_MULTIPLIER_1_OPTION_SCREEN_POINT, screen.presses)


if __name__ == "__main__":
    unittest.main()
