from dotenv import load_dotenv
from smhi.conn import get_engine
from smhi.seed.station import seed_weather_stations
from smhi.seed.station_data import seed_weather_data

from smhi.models import Base, WeatherData, WeatherStation

def init_db(engine):
    WeatherData.__table__.drop(engine)
    WeatherStation.__table__.drop(engine)
    Base.metadata.create_all(bind=engine)

def seed_database(engine):
    seed_weather_stations(engine)
    seed_weather_data(engine)

if __name__ == "__main__":
    engine = get_engine()
    init_db(engine)
    seed_database(engine)
    engine.dispose()