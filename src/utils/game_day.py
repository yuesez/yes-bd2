"""Single source for the Brown Dust II game-day boundary.

The server refreshes daily content at 08:00 UTC+8 (00:00 UTC, no DST): the
in-game mission timer and the trade stock refresh both confirm it.  Weekly
content refreshes at the same hour on Monday.
"""

from datetime import datetime, timedelta, timezone

GAME_TZ = timezone(timedelta(hours=8))
DAILY_REFRESH_HOUR = 8


def game_day_weekday(now: datetime | None = None) -> int:
    """The game day's weekday: Monday is 0, Sunday is 6.

    A game day runs 08:00 UTC+8 to 08:00 the next day, so 02:00 on a Tuesday is
    still Monday's game day.  A naive timestamp is read as UTC+8, which is the
    clock the game's own times are written in.
    """
    if now is None:
        now = datetime.now(timezone.utc)
    elif now.tzinfo is None:
        now = now.replace(tzinfo=GAME_TZ)
    game_day = now.astimezone(GAME_TZ) - timedelta(hours=DAILY_REFRESH_HOUR)
    return game_day.weekday()
