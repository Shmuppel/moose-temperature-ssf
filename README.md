# moose-temperature-ssf

## Analysis

## SMHI Database Setup

To handle SMHI data efficiently we set up a (mock) database that stores data retrieved from their API.
Install PostgreSQL and make sure to enable the PostGIS extension by running the following whilst in psql:

`CREATE EXTENSION postgis`

The database can then be seeded with weather data by running `python3 smhi/main.py`, this should take a while. If you want to download additional weather covariates, the mapping can be found in `smhi/seed/station` under `PARAMETERS`.

## TODO

- Update SMHI package dependencies in pyproject.toml
- Update SMHI readme

## Future

- add distance to coast to air temperature prediction
- add atmospheric condition (e.g. cloud cover) to air temperature prediction
- add irradiance to air temperature prediction
- add irradiance as covariate to point data (?)
- look into good ways to interpolate precipitation, if any
- look into good ways to interpolate wind, if any (known effect on non-wild moose)
- poly in elevation?

- collar temp - air temp to see body heat cycle?

2012-01-23 00:00:00 -21.8 -3.33
