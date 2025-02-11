# System imports
from io import StringIO

# Third-party imports
import pandas as pd
import numpy as np
from requests import Session
from requests_cache import CacheMixin
from requests_ratelimiter import LimiterMixin
from sqlalchemy import insert, select
import sqlalchemy.orm as orm

# Local imports
from database.util.multiprocessing import BaseWorker, BaseManager
from database.weather.models import WeatherData, WeatherStation


class CachedLimiterSession(CacheMixin, LimiterMixin, Session):
    """Session class with caching and rate-limiting behavior."""
    pass


class WeatherDataWorker(BaseWorker):
    """
    Worker process that fetches and processes weather data.
    Each worker has its own engine and session.
    """
    def __init__(self, *args):
        self.smhi_cache = None
        super().__init__(*args)
    
    def run(self):
        self.smhi_cache = CachedLimiterSession('database/weather/cache', per_second=2)
        super().run()

    def process_job(self, station_id: int) -> None:
        """Fetch and process weather data for a station."""
        with orm.Session(self.engine) as db_session:
            station = db_session.get(WeatherStation, station_id)
            if not station:
                return
            station_data = self.fetch_weather_station_data(station)
            if station_data:
                db_session.execute(insert(WeatherData), station_data)
                db_session.commit()

    def fetch_weather_station_data(self, weather_station: WeatherStation) -> list[dict[str, any]] | None:
        """Fetch and process weather data for a specific station."""
        response = self.smhi_cache.get(weather_station.data_url)
        if response.status_code != 200:
            raise ConnectionError(f"Failed to fetch data for station {weather_station.key}")

        file = StringIO(response.content.decode())

        # Skip header lines
        for line in file:
            if line.startswith('Datum'):
                break

        df = pd.read_csv(
            file, sep=';', header=0, index_col=False,
            usecols=[0, 1, 2, 3],
            names=["date", "time", "value", "quality"],
            dtype={'date': str, 'time': str, 'value': np.float32, 'quality': str}
        )

        # Handle edge cases where data is missing or formatted unusually
        df = df[(df['date'] != '') & df['date'].notna()]
        if df.empty:
            # print(f"All rows in weather station - {weather_station.id} are NA.")
            return None

        # Combine 'date' and 'time' columns into a single datetime column
        df["date"] = pd.to_datetime(df["date"] + " " + df["time"], format="%Y-%m-%d %H:%M:%S")
        # TODO remove
        df = df[df["date"] >= pd.Timestamp("2002-01-01")]

        # Add additional columns derived from the WeatherStation object
        df["weather_station_id"] = weather_station.id
        df["parameter"] = weather_station.parameter
        df = df[["weather_station_id", "date", "parameter", "value", "quality"]]

        return df.to_dict(orient="records")


class WeatherDataManager(BaseManager):
    """Manager class to handle queue, progress tracking, and worker processes."""

    def create_jobs(self) -> None:
        """Add station IDs to the queue."""
        with orm.Session(self.engine) as session:
            for id in session.scalars(select(WeatherStation.id)).all():
                self.job_queue.put(id)
                self.total_jobs += 1


def seed_weather_data(engine) -> None:
    """Run the full seeding process for weather stations and data."""
    manager = WeatherDataManager(engine, num_workers=20, title="Seeding Weather Data")
    manager.run(WeatherDataWorker)
