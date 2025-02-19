# ------------------------------------------------------------------------------
# Script: Weather Kriging and Moose Localisation Prediction
# Description:
#   Builds a space–time kriging model for weather data and predicts weather 
#   values at moose localisations using kriging of residuals.
#
# Author: Niels van der Vegt
# Date: 2025-02-19
# ------------------------------------------------------------------------------

# --------------------------
# 1. Library Imports & Global Settings
# --------------------------

library(tidyverse)

# Load additional required packages
packages <- c("sp", "sf", "gstat", "dbplyr", "meteo", "spacetime", "bestNormalize",
              "glue", "parallel", "parabar", "pbapply", "ragg")
walk(packages, require, character.only = TRUE)

# Set seed and timezone
set.seed(20240703) 
Sys.setenv(TZ = 'Europe/Stockholm')

# --------------------------
# 2. Weather Kriging Functions
# --------------------------

# Build the weather kriging model.
# This function performs:
#   - Creation of a space–time data frame (STFDF)
#   - Fitting of the empirical variogram and a sum–metric variogram model
# Returns a list with key objects for prediction.
build_weather_kriging_model <- function(weather_data, parameter = "air_temperature") {
  
  # Create a space–time data frame (STFDF)
  create_stfdf <- function(weather_data) {
    stations <- weather_data %>% distinct(station_id, x, y)
    obs      <- weather_data %>% select(station_id, date, value, res)
    obs      <- as.data.frame(obs)
    stations <- as.data.frame(stations)
    
    stfdf <- meteo::meteo2STFDF(
      obs,
      stations,
      obs.staid.time       = c("station_id", "date"),
      stations.staid.lon.lat = c("station_id", "x", "y"),
      crs                  = CRS('epsg:3006')
    )
    
    # Remove duplicates using zerodist
    zd <- zerodist(stfdf@sp)
    if (nrow(zd) > 0) {
      stfdf <- stfdf[-zd[,2], ]
    }
    return(stfdf)
  }
  
  # Fit the variogram to the space–time data
  fit_variogram <- function(weather_stfdf) {
    diff_time <- as.integer(diff(index(weather_stfdf@time))[1])
    tlags <- 0:ceiling(10 / diff_time)
    
    empirical_variogram <- variogramST(res ~ 1, weather_stfdf, tlags = tlags, progress = FALSE)
    empirical_variogram$timelag <- as.numeric(empirical_variogram$timelag)
    
    # Estimate spatial anisotropy
    linear_st_anisotropy <- estiStAni(empirical_variogram, c(100000, 400000), t.range = 10)
    
    # Define the sum–metric variogram model (parameters based on visual inspection)
    sum_metric_model <- vgmST("sumMetric",
                              space = vgm(psill = 6, model = "Sph", range = 550000, nugget = 1),
                              time  = vgm(psill = 30, model = "Sph", range = 10,     nugget = 1), 
                              joint = vgm(psill = 4,  model = "Sph", range = 50000,  nugget = 1),
                              stAni = linear_st_anisotropy)
    
    # Fit the sum–metric model to the empirical variogram
    fit_sum_metric_model <- fit.StVariogram(
      empirical_variogram, 
      sum_metric_model, 
      lower      = c(0, 0.001, 0, 0.01, 1),
      fit.method = 8
    )
    attr(fit_sum_metric_model, "temporal unit") <- "hours"
    
    # Uncomment below to save variogram plots if desired
    # file_name <- paste0('03_variograms/', weather_stfdf@endTime[1], ".png")
    # agg_png(file_name)
    # plot(empirical_variogram, fit_sum_metric_model, wireframe = TRUE, all = TRUE, scales = list(arrows = FALSE))
    # dev.off()
    
    return(fit_sum_metric_model)
  }
  
  # Main steps within build_weather_kriging_model
  weather_stfdf  <- create_stfdf(weather_data)
  variogram_model <- fit_variogram(weather_stfdf)
  
  list(
    weather_stfdf   = weather_stfdf,
    variogram_model = variogram_model
  )
}

# --------------------------
# 3. Child Worker Function
# --------------------------

predict_weather_at_localisations <- function(localisations, kriging_model, maxdist = 200000, nmax = 5) {
  
  # Create spatio–temporal object for localisations
  create_moose_st <- function(localisations) {
    localisations <- as.data.frame(localisations)
    moose_sf <- st_as_sf(
      localisations, 
      coords = c("x", "y"), 
      crs = CRS('epsg:3006')
    )
    spatial_points <- as(moose_sf, "Spatial")
    st_obj <- stConstruct(
      localisations, 
      space = c("x", "y"), 
      time  = "time", 
      spatial_points,
      crs   = CRS('epsg:3006')
    )
    return(st_obj)
  }
  
  # Perform space–time kriging for residuals
  krige_residuals <- function(kriging_model, moose_st, maxdist, nmax) {
    krige_result <- krigeST(
      res ~ 1, 
      kriging_model$weather_stfdf, 
      moose_st,
      kriging_model$variogram_model, 
      maxdist    = maxdist,
      nmax       = nmax, 
      computeVar = FALSE,  # TODO: incorporate variance computation if needed
      progress   = FALSE
    )
    return(krige_result@data$var1.pred)
  }
  
  # Main steps in predict_weather_at_localisations
  moose_st <- create_moose_st(localisations)
  predicted_res <- krige_residuals(kriging_model, moose_st, maxdist, nmax)
  
  # Combine the regression prediction with the kriged residuals
  pred_combined <- predicted_res + localisations$res
  return(pred_combined)
}


# --------------------------
# 3. Data Preparation Functions
# --------------------------

# Prepare start steps for localisation prediction
prepare_start_steps <- function(df) {
  df <- df %>%
    mutate(
      x    = x1_,
      y    = y1_,
      time = t1_,
      res  = res_start
    ) %>%
    arrange(time)
  return(df)
}

# Prepare end steps for localisation prediction
prepare_end_steps <- function(df) {
  df <- df %>%
    mutate(
      x    = x2_,
      y    = y2_,
      time = t2_,
      res  = res_end
    ) %>%
    arrange(time)
  return(df)
}


# --------------------------
# 4. Batch Processing Function
# --------------------------

process_batch <- function(batch) {
  batch_id    <- batch$id
  moose_data  <- batch$moose_data
  weather_data <- batch$weather_data
  
  logger(glue("Processing {batch_id}"))
  
  logger(glue("Building Kriging Model"))
  kriging_model <- build_weather_kriging_model(weather_data, "air_temperature")
  
  logger(glue("Predicting start steps"))
  start_steps <- prepare_start_steps(moose_data)
  unique_start_steps <- start_steps %>% distinct(
    id, animal_id, step_id_, x, y, time, res, x1_, y1_, t1_
  )
  unique_start_steps$temperature_start <- predict_weather_at_localisations(
    unique_start_steps, 
    kriging_model,
    maxdist = 200000,
    nmax    = 5
  )
  
  logger(glue("Predicting end steps"))
  end_steps <- prepare_end_steps(moose_data)
  end_steps$temperature_end <- predict_weather_at_localisations(
    end_steps, 
    kriging_model,
    maxdist = 200000, 
    nmax    = 5
  )
  
  # Join predictions with the original moose data
  logger(glue("Adding predictions to moose data"))
  unique_start_steps <- unique_start_steps %>% select(id, temperature_start)
  end_steps <- end_steps %>% select(id, temperature_end)
  
  moose_data <- left_join(moose_data, unique_start_steps, by = "id")
  moose_data <- left_join(moose_data, end_steps, by = "id")
  moose_data <- moose_data %>% select(id, temperature_start, temperature_end)
  
  logger(glue("Finished processing {batch_id}"))
  return(moose_data)
}


# --------------------------
# 5. Utility Functions (Result Writer & Logger)
# --------------------------

# Create a result writer (CSV appender)
make_result_writer <- function(path, ext = "csv", mode = "w") {
  pid <- Sys.getpid()
  full_path <- paste0(path, "_", pid, ".", ext)
  conn_result <<- file(full_path, open = mode)
  
  write_result <<- function(input) {
    write.table(
      input, conn_result, sep = ";", row.names = FALSE, 
      col.names = FALSE, append = TRUE
    )
    flush(conn_result)
  }
}

# Create a logger (writes text logs)
make_logger <- function(path, ext = "txt", mode = "w") {
  pid <- Sys.getpid()
  full_path <- paste0(path, "_", pid, ".", ext)
  conn_log <<- file(full_path, open = mode)
  
  logger <<- function(input) {
    writeLines(input, conn_log)
    flush(conn_log)
  }
}


# --------------------------
# 6. Main Function
# --------------------------

main <- function() {
  # Load week batches data
  load('data/week_batches.RData')
  # Start the parallel backend (adjust cores as needed)
  backend <- start_backend(cores = 59, cluster_type = "fork")
  
  # Load required libraries on backend workers
  evaluate(backend, {
    library(dplyr)
    library(lubridate)
    library(sf)
    library(gstat)
    library(spacetime)
    library(meteo)
    library(sp)
    library(glue)
  })
  
  # Export functions to backend workers
  export(backend, c(
    "prepare_start_steps", 
    "prepare_end_steps",
    "build_weather_kriging_model", 
    "predict_weather_at_localisations",
    "process_batch",
    "make_result_writer", 
    "make_logger"
  ), environment())
  
  evaluate(backend, make_logger("log/worker"))
  # Configure progress bar settings
  configure_bar(
    type   = "modern", 
    format = ":spin [:bar] :current/:total :percent [:elapsedfull / :eta]"
  )
  
  options(cli.ignore_unknown_rstudio_theme = TRUE)
  options(stop_forceful = TRUE)
  
  # Process batches in parallel
  results <- par_lapply(backend, week_batches, process_batch)
  results <- bind_rows(results)
  write.csv(results, './03_results.csv')
  # Stop the backend
  stop_backend(backend)
}

# Uncomment the following line to run the main function when executing the script
main()
