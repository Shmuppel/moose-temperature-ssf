import pandas as pd
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session
from geoalchemy2 import RasterElement
import geoalchemy2.functions as gfunc

from smhi.models import WeatherData, WeatherStation

def get_weather_data_at_time(
        session: Session,
        timestamp: datetime,
        parameter: str
    ):
    ...

def get_weather_data_in_time_range(
        session: Session,
        time_range: list[datetime],
        parameter: str
    ):
    query = (
       select(
           WeatherData,
           WeatherStation, 
           gfunc.ST_X(WeatherStation.geom).label("x"),
           gfunc.ST_Y(WeatherStation.geom).label("y")
        )
        .join(WeatherStation, WeatherData.weather_station_id == WeatherStation.id)
        .where(WeatherData.parameter == parameter)
        .where(WeatherData.date >= time_range[0])
        .where(WeatherData.date <= time_range[1])
    )
    
    weather_data = session.execute(query).fetchall()
    breakpoint()
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