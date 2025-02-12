from datetime import datetime, timedelta, timezone

def get_rounded_hour(t: datetime) -> datetime:
    # Rounds to nearest hour by adding a timedelta hour if minute >= 30
    return (t.replace(second=0, microsecond=0, minute=0, hour=t.hour)+timedelta(hours=t.minute//30))

def get_millisecond_datetime(milliseconds: int) -> datetime:
    """Convert UNIX timestamp in milliseconds to Python datetime."""
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc)
