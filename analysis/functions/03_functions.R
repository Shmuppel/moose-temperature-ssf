# Build the weather kriging model.
# This function wraps the following sub-steps:
#   - Creating a space–time data frame (STFDF).
#   - Fitting the empirical variogram and then a sum–metric variogram model.
#
# It returns a list with the key objects for later use in prediction.
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
      obs.staid.time = c("station_id", "date"),
      stations.staid.lon.lat = c("station_id", "x", "y"),
      crs = CRS('epsg:3006')
    )
    # Remove duplicates using zerodist
    zd <- zerodist(stfdf@sp)
    if (nrow(zd) > 0) stfdf <- stfdf[-zd[,2], ]
    return(stfdf)
  }
  
  fit_variogram <- function(weather_stfdf) {
    diff_time <- as.integer(diff(index(weather_stfdf@time))[1])
    tlags <- 0:ceiling(10 / diff_time)
    empirical_variogram <- variogramST(res ~ 1, weather_stfdf, tlags = tlags, progress=F)
    empirical_variogram$timelag <- as.numeric(empirical_variogram$timelag)
    
    # Estimate spatial anisotropy
    linear_st_anisotropy <- estiStAni(empirical_variogram, c(100000, 400000), t.range = 10)
    
    # Define the sum-metric variogram model (with parameters from visual inspection)
    sum_metric_model <- vgmST("sumMetric",
                              space=vgm(psill=6, "Sph", range=550000, nugget=1),
                              time= vgm(psill=30, "Sph", range=10, nugget=1), 
                              joint= vgm(psill=4, "Sph",  range=50000, nugget=1),
                              stAni=linear_st_anisotropy)
    
    # Fit the sum-metric model to the empirical variogram
    fit_sum_metric_model <- fit.StVariogram(
      empirical_variogram, 
      sum_metric_model, 
      lower = c(0, 0.001, 0, 0.01, 1),
      fit.method = 8
    )
    attr(fit_sum_metric_model, "temporal unit") <- "hours"
    
    #file_name = paste0('03_variograms/', weather_stfdf@endTime[1], ".png")
    #agg_png(file_name)
    #plot(empirical_variogram, fit_sum_metric_model, wireframe=T, all=T, scales=list(arrows=F))
    #dev.off()
    
    return(fit_sum_metric_model)
  }
  
  # ---- Main steps within build_weather_kriging_model ----
  weather_stfdf <- create_stfdf(weather_data)
  variogram_model <- fit_variogram(weather_stfdf)
  
  list(
    weather_stfdf     = weather_stfdf,
    variogram_model   = variogram_model
  )
}

# Function 2: Predict weather values at moose localisations.
# This function internally splits the work into sub-steps:
#   - Preparing the localisation data (computing GTT and regression predictions).
#   - Constructing a spatio-temporal object for the localisations.
#   - Kriging the residuals using the fitted variogram model.
#   - Combining the regression prediction and kriged residuals,
#     and applying the inverse power transformation.
predict_weather_at_localisations <- function(
    localisations,
    kriging_model,
    maxdist = 200000, 
    nmax = 5
) {
  
  # Build spatio-temporal object for localisations
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
      computeVar = F, # TODO incorporate
      progress = F
    )
    return(krige_result@data$var1.pred)
  }
  
  # ---- Main steps within predict_weather_at_localisations ----
  moose_st <- create_moose_st(localisations)
  predicted_res <- krige_residuals(kriging_model, moose_st, maxdist, nmax)
  pred_combined <- predicted_res + localisations$res
  return(pred_combined)
}

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

# MAIN
main <- function() {
  backend <- start_backend(cores = 1, cluster_type = "fork")
  
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
  
  export(backend,c(
    "prepare_start_steps", 
    "prepare_end_steps",
    "build_weather_kriging_model", 
    "predict_weather_at_localisations",
    "process_batch",
    "make_result_writer", 
    "make_logger"
  ),environment())
  
  evaluate(backend, make_logger("log/worker"))
  evaluate(backend, make_result_writer("03_results/result"))
  
  # Configure the progress bar
  configure_bar(
    type = "modern", 
    format = ":spin [:bar] :current/:total :percent [:elapsedfull /:eta]"
  )
  
  options(cli.ignore_unknown_rstudio_theme = TRUE)
  options(stop_forceful = TRUE)
  par_lapply(backend, week_batches, process_batch)
  
  stop_backend(backend)
}