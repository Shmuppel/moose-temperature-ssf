# Standard library imports
import json
import os
from typing import List, Dict

# Third-party imports
from alive_progress import alive_bar
import sqlalchemy.orm as orm
from requests import Session
from requests_cache import CacheMixin
from requests_ratelimiter import LimiterMixin
from pyproj import Transformer

# Local imports
from smhi.util.time import get_millisecond_datetime
from smhi.models import WeatherStation


class CachedLimiterSession(CacheMixin, LimiterMixin, Session):
    """
    Session class with caching and rate-limiting behavior.
    Useful for development when the database needs frequent reseeding.
    """
    pass


SESSION = CachedLimiterSession(
    cache_name="cache", 
    per_second=2
)

# Constants for API endpoint and weather parameters
# Add or remove parameters here in order to use them (https://opendata.smhi.se/apidocs/metobs/parameter.html)
ENTRY_POINT = "https://opendata-download-metobs.smhi.se/api/version/1.0"
PARAMETER_MAPPING = {
    "air_temperature": 1,
    "wind": 4,
    "precipitation": 7,
    "snow_depth": 8,
    "global_irradiance": 11,
    "total_cloud_amount": 16
}

# Transformer for coordinates
TRANSFORMER = Transformer.from_crs("EPSG:4326", "EPSG:3006", always_xy=True)

def get_station_data_url(station: Dict) -> str:
    """Extract and return the data URL for the station's corrected-archive."""
    station_url = None
    for link in station["link"]:
        if link['type'] == 'application/json':
            station_url = link["href"]
            break

    response = SESSION.get(station_url)
    station_periods = response.json()['period']

    period_url = None
    for period in station_periods:
        if period["key"] == "corrected-archive":
            for link in period["link"]:
                if link["type"] == 'application/json':
                    period_url = link["href"]
                    break

    if not period_url:
        raise ValueError(f"No link to corrected-archive for station {station['key']}")
    
    return SESSION.get(period_url).json()['data'][0]["link"][0]["href"]


def build_weather_station_data(station: Dict, parameter: str) -> WeatherStation:
    """Build and return a WeatherStation object from raw API data."""
    x, y = TRANSFORMER.transform(station['longitude'], station['latitude'])
    
    return WeatherStation(
        key=station["key"],
        title=station["title"],
        summary=station["summary"],
        owner=station["owner"],
        measuring_stations=station["measuringStations"],
        parameter=parameter,
        active=bool(station["active"]),
        updated=get_millisecond_datetime(station["updated"]),
        time_from=get_millisecond_datetime(station["from"]),
        time_to=get_millisecond_datetime(station["to"]),
        geom=f"SRID=3006;POINT({x} {y})",
        height=station['height'],
        data_url=get_station_data_url(station)
    )


def fetch_weather_stations() -> List[WeatherStation]:
    """Fetch and process weather stations for a given parameter."""
    stations = []
    stations_per_parameter = {}
    n_stations = 0

    for parameter in json.loads(os.getenv('PARAMETERS')):
        response = SESSION.get(f"{ENTRY_POINT}/parameter/{PARAMETER_MAPPING[parameter]}.json").json()
        print(parameter, PARAMETER_MAPPING[parameter])
        stations_per_parameter[parameter] = response
        n_stations += len(response["station"])
        
    with alive_bar(n_stations, title=f"Seeding Weather Stations", bar="filling") as bar:
        for parameter in stations_per_parameter.keys():
            bar.text(parameter)
            for station in stations_per_parameter[parameter]["station"]:
                try:
                    stations.append(build_weather_station_data(station, parameter))
                except ValueError as e:
                    print(f"Error processing station {station['key']}: {e}")
                bar()

    return stations


def seed_weather_stations(engine) -> None:
    """Seed weather station data into the database."""
    station_rows = fetch_weather_stations()
    
    with orm.Session(engine) as session:
        session.add_all(station_rows)
        session.commit()

