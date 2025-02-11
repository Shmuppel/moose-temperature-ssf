import pandas as pd
from datetime import datetime

from sqlalchemy import select, insert
from sqlalchemy.orm import Session
from geoalchemy2 import RasterElement
import geoalchemy2.functions as gfunc

from .kriging import UniversalKriger
from .models import WeatherData, WeatherStation, KrigedWeather
from database.util.raster import get_wkb_raster_from_arrays
from database.util.time import get_rounded_hour

def get_weather_data(
        session: Session, 
        timestamp: datetime | list[datetime], 
        parameter: str
    ):
    """
    """
    query = (
       select(
            WeatherData.value,
            WeatherData.date,
            WeatherStation.height,
            WeatherStation.landuse,
            gfunc.ST_X(WeatherStation.geom).label("x"),
            gfunc.ST_Y(WeatherStation.geom).label("y")
        )
        .join(WeatherStation, WeatherData.weather_station_id == WeatherStation.id)
        .where(WeatherData.parameter == parameter)
    )

    if type(timestamp) == datetime:
        query = query.where(WeatherData.date == timestamp)
    elif type(timestamp) == list:
        query = query\
            .where(WeatherData.date >= timestamp[0])\
            .where(WeatherData.date <= timestamp[1])
    else:
        raise ValueError("timestamp argument not of type datetime or list of datetimes")
    
    weather_data = session.execute(query).fetchall()
    weather_df = pd.DataFrame(weather_data, columns=["value", "date", "elevation", "landuse", "x", "y"])
    return weather_df

def get_nearest_value_to_point(
        session: Session, 
        parameter: str, 
        timestamp: datetime, 
        x: int, 
        y: int,
        search_radius_km: float = 150.0
    ):
    weather_data_query = (
        select(
            WeatherData.value,
            gfunc.ST_Distance(
                WeatherStation.geom,
                gfunc.ST_SetSRID(gfunc.ST_MakePoint(x, y), 3006)
            ).label("distance")
        )
        .join(WeatherStation, WeatherData.weather_station_id == WeatherStation.id)
        .where(WeatherData.parameter == parameter)
        .where(WeatherData.date == timestamp)
        .order_by("distance")
    )
    # Limit the search to the given radius
    weather_data_query = weather_data_query.where(
        gfunc.ST_Distance(
            WeatherStation.geom,
            gfunc.ST_SetSRID(gfunc.ST_MakePoint(x, y), 3006)
        ) <= search_radius_km * 1000
    )
    # Fetch the nearest weather data record
    nearest_weather_data = session.execute(weather_data_query).first()

    if nearest_weather_data:
        return nearest_weather_data[0]
    return None


def get_kriged_value_at_point(
        session: Session, 
        parameter: str, 
        date: datetime, 
        method: str,
        x: int, 
        y: int
    ):
    """
    """
    query = (
        select(
            gfunc.ST_Value(
                KrigedWeather.raster, 
                gfunc.ST_SetSRID(gfunc.ST_MakePoint(x, y), 3006)
            )
        )
        .where(KrigedWeather.parameter == parameter)
        .where(KrigedWeather.method == method)
        .where(KrigedWeather.date == date)
    )

    result = session.execute(query).scalar()

    return result

def get_weather_at_point(
        session: Session,
        parameter: str,
        timestamp: datetime,
        x,
        y
    ) -> int:
    timestamp = get_rounded_hour(timestamp)

    if parameter == "nearest_air_temperature":
        return get_nearest_value_to_point(session, "air_temperature", timestamp, x, y)
    
    if parameter == "air_temperature":
        return get_kriged_value_at_point(session, parameter, timestamp, 'regression', x, y)
    
    if parameter == "precipitation":
        return get_nearest_value_to_point(session, parameter, timestamp, x, y)

    if parameter == "wind":
        return get_kriged_value_at_point(session, parameter, timestamp, 'regression', x, y)
    
    if parameter == "snow_depth":
        # Snow depth is given once a day at 06:00
        timestamp = timestamp.replace(hour=6, minute=0, second=0, microsecond=0)
        return get_kriged_value_at_point(session, parameter, timestamp, 'regression', x, y)