import os
from dotenv import load_dotenv
from sqlalchemy import create_engine
import logging

logging.basicConfig()
logging.getLogger("sqlalchemy.engine.Engine.smhi").setLevel(logging.INFO)

load_dotenv()

def get_engine():
    """Create and return the database engine."""
    config = {
        "host": os.getenv("DB_HOST"),
        "database": os.getenv("DB_NAME"),
        "user": os.getenv("DB_USER"),
        "password": os.getenv("DB_PASSWORD")
    }
    engine = create_engine(f'postgresql+psycopg2://{config["user"]}:{config["password"]}@{config["host"]}/{config["database"]}')
    return engine
