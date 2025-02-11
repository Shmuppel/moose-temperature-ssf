# Standard library imports
from typing import List, Dict

# Third-party imports
import rasterio
import sqlalchemy.orm as orm
from requests import Session
from requests_cache import CacheMixin
from requests_ratelimiter import LimiterMixin
from pyproj import Transformer

# Local imports
from database.base import get_engine
from database.util.time import get_millisecond_datetime
from database.weather.models import WeatherStation

landuse_classes = {
    1: "Coniferous forest",
    2: "Dedicious & mixed forest",
    3: "Clear-cut & young forest",
    4: "Open",
    5: "Wetland",
    6: "Water bodies",
    7: "Anthropogenic",
    8: "Low mountain forest",
}
class CachedLimiterSession(CacheMixin, LimiterMixin, Session):
    """
    Session class with caching and rate-limiting behavior.
    Useful for development when the database needs frequent reseeding.
    """
    pass


SESSION = CachedLimiterSession(
    cache_name="database/weather/cache", 
    per_second=2
)

# Constants for API endpoint and weather parameters
# Add or remove parameters here in order to use them (https://opendata.smhi.se/apidocs/metobs/parameter.html)
ENTRY_POINT = "https://opendata-download-metobs.smhi.se/api/version/1.0"
PARAMETERS = {
    "air_temperature": 1,
    "wind": 4,
    "precipitation": 7,
    "snow_depth": 8,
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
        landuse=get_station_landuse(x, y, get_millisecond_datetime(station["from"])),
        data_url=get_station_data_url(station)
    )

def get_station_landuse(x, y, datetime):
    year = 2003 if datetime.year < 2018 else 2018
    raster_dir = "data/geography/landuse/classified/"
    raster_file = "landuse_2018/landuse_c_2018.tif" if year == 2018 else "landuse_2003-2017/landuse_c_2003-2017_EPSG3006.tif"
    raster_path = raster_dir + raster_file

    with rasterio.open(raster_path, nodata=255) as src:
        for val in src.sample([(x, y)]): 
            return None if val == 255 else landuse_classes[int(val)]

def fetch_weather_stations(parameter: str) -> List[WeatherStation]:
    """Fetch and process weather stations for a given parameter."""
    response = SESSION.get(f"{ENTRY_POINT}/parameter/{PARAMETERS[parameter]}.json").json()
    stations = []
    
    for station in response["station"]:
        try:
            stations.append(build_weather_station_data(station, parameter))
        except ValueError as e:
            print(f"Error processing station {station['key']}: {e}")
    
    print(f"Processed {len(stations)} weather stations for parameter: {parameter}")
    return stations


def seed_weather_stations(engine) -> None:
    """Seed weather station data into the database."""
    station_rows = []
    for parameter in PARAMETERS.keys():
        station_rows.extend(fetch_weather_stations(parameter))
    
    with orm.Session(engine) as session:
        session.add_all(station_rows)
        session.commit()
    print(f"Seeded {len(station_rows)} weather stations.")

