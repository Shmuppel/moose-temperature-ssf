# moose-temperature-ssf

## Analysis

## SMHI Database Setup

To handle SMHI data efficiently we set up a (mock) database that stores data retrieved from their API.
Install PostgreSQL and make sure to enable the PostGIS extension by running the following whilst in psql:

`CREATE EXTENSION postgis`

The database can then be seeded with weather data by running `python3 smhi/main.py`, this should take a while. If you want to download additional weather covariates, the mapping can be found in `smhi/seed/station` under `PARAMETERS`.

## Analysis

Analyses can be run through quarto notebooks in the analyis folder. Previously carried
out analyses can be found in analysis_pdf folder where the renders of the quarto notebooks can be found.

## Running Parallel Kriging on a Droplet

Install packages like so:

```
sudo apt-get update
sudo apt-get install r-base

sudo apt install libssl-dev libcurl4-openssl-dev unixodbc-dev libxml2-dev libmariadb-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev libudunits2-dev cmake gdal-bin

# Fix libgdal-dev thing

Sudo apt install libgdal-dev

sudo R -e 'install.packages("xml2", dependencies = T, INSTALL_opts = c("--no-lock"))'
sudo R -e 'install.packages("tidyverse")'
```
