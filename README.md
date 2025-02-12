# moose-temperature-ssf

## Analysis

## SMHI Database Setup

To handle SMHI data efficiently we set up a (mock) database that stores data retrieved from their API.
Install PostgreSQL and make sure to enable the PostGIS extension by running the following whilst in psql:

`CREATE EXTENSION postgis`

The database can then be seeded with weather data by running `python3 smhi/main.py`, this should take a while. If you want to download additional weather covariates, the mapping can be found in `smhi/seed/station` under `PARAMETERS`.

## TODO

Update SMHI package dependencies in pyproject.toml  
Update SMHI readme
