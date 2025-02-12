from datetime import datetime
from typing import List
from sqlalchemy import String, DateTime, Float, ForeignKey, Integer, Boolean
from sqlalchemy.orm import Mapped, relationship, mapped_column
from geoalchemy2 import Geometry, WKBElement
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class WeatherStation(Base):
    __tablename__ = 'weather_station'
    id: Mapped[int] = mapped_column(primary_key=True)

    key: Mapped[int] = mapped_column(Integer)
    title: Mapped[str] = mapped_column(String)
    summary: Mapped[str] = mapped_column(String)
    owner: Mapped[str] = mapped_column(String(100))  # "SMHI", "Icke namngiven ägare", "Swedavia"
    measuring_stations = mapped_column(String(10))  # CORE or ADDITIONAL

    parameter: Mapped[str] = mapped_column(String(30), index=True) # air_temperature, wind, precipitation

    active: Mapped[bool] = mapped_column(Boolean)
    updated: Mapped[datetime] = mapped_column(DateTime())
    time_from: Mapped[datetime] = mapped_column(DateTime())
    time_to: Mapped[datetime] = mapped_column(DateTime())

    # Covariates
    height: Mapped[Float] = mapped_column(Float)

    geom: Mapped[WKBElement] = mapped_column(Geometry("Point", srid=3006, spatial_index=True), nullable=True)

    data_url: Mapped[str] = mapped_column(String)
    data: Mapped[List["WeatherData"]] = relationship(back_populates="weather_station")


class WeatherData(Base):
    __tablename__ = 'weather_data'
    id: Mapped[int] = mapped_column(primary_key=True)
    weather_station: Mapped["WeatherStation"] = relationship(back_populates="data")
    weather_station_id: Mapped[int] = mapped_column(ForeignKey("weather_station.id"), index=True)
    date: Mapped[datetime] = mapped_column(DateTime())
    date_local: Mapped[datetime] = mapped_column(DateTime(), index=True)
    parameter: Mapped[str] = mapped_column(String(30), index=True) # air_temperature, wind, precipitation
    value: Mapped[float] = mapped_column(Float) # air_temperature, wind, precipitation
    quality: Mapped[str] = mapped_column(String(3))
