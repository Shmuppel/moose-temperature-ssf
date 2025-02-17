# Function 1: Build the weather kriging model.
# This function wraps the following sub-steps:
#   - Determining the time period from the localisation data.
#   - Retrieving and processing weather data.
#   - Fitting a regression model and applying the Yeo-Johnson power transform.
#   - Creating a space–time data frame (STFDF).
#   - Fitting the empirical variogram and then a sum–metric variogram model.
#
# It returns a list with the key objects for later prediction.
build_weather_kriging_model <- function(weather_data, parameter = "air_temperature") {
  
  # Fit regression and transform data 
  fit_regression <- function(weather_data) {
    power_trans <- yeojohnson(weather_data$value)
    weather_data$value_trans <- predict(power_trans)
    lin_mod <- lm(value_trans ~ elevation + gtt, data = weather_data)
    weather_data$res <- resid(lin_mod)
    
    list(
      model = lin_mod, 
      power_trans = power_trans, 
      weather_data = weather_data
    )
  }
  
  # Create a space–time data frame (STFDF)
  create_stfdf <- function(weather_data) {
    stations <- weather_data %>% distinct(station_id, x, y)
    obs      <- weather_data %>% select(station_id, date, value, elevation, gtt, res)
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
  
  # Fit the variogram
  fit_variogram <- function(weather_stfdf) {
    diff_time <- as.integer(diff(index(weather_stfdf@time))[1])
    tlags <- 0:ceiling(10 / diff_time)
    empirical_variogram <- variogramST(res ~ 1, weather_stfdf, tlags = tlags, progress=F)
    empirical_variogram$timelag <- as.numeric(empirical_variogram$timelag)
    
    # Estimate spatial anisotropy
    linear_st_anisotropy <- estiStAni(empirical_variogram, c(100000, 400000), t.range = 10)
    
    # Define the sum-metric variogram model (with parameters from visual inspection)
    sum_metric_model <- vgmST("sumMetric",
                              space = vgm(psill = 16, "Sph", range = 550000, nugget = 1),
                              time  = vgm(psill = 7,  "Sph", range = 10,     nugget = 1), 
                              joint = vgm(psill = 15, "Sph", range = 50000,  nugget = 1),
                              stAni = linear_st_anisotropy)
    
    # Fit the sum-metric model to the empirical variogram
    fit_sum_metric_model <- fit.StVariogram(
      empirical_variogram, 
      sum_metric_model, 
      lower = c(0, 0.001, 0, 0.01, 1),
      fit.method = 8
    )
    attr(fit_sum_metric_model, "temporal unit") <- "hours"
    return(fit_sum_metric_model)
  }
  
  # ---- Main steps within build_weather_kriging_model ----
  # 1. Add variables to weather data
  weather_data$gtt <- temp_geom(weather_data$day, weather_data$lat, variable = "mean")
  
  # 2. Fit regression and transform data
  reg_results <- fit_regression(weather_data)
  weather_data <- reg_results$weather_data
  linear_regression <- reg_results$model
  power_transform <- reg_results$power_trans
  
  # 3. Create space-time data frame
  weather_stfdf <- create_stfdf(weather_data)
  
  # 4. Fit the variogram model
  variogram_model <- fit_variogram(weather_stfdf)
  
  # Return all the key objects needed for prediction
  list(
    linear_regression = linear_regression,
    power_transform   = power_transform,
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
  # Compute linear regression predictions at localisations
  prepare_localisation_predictions <- function(localisations, reg_model) {
    localisations$pred_lin <- predict(reg_model, localisations)
    return(localisations)
  }
  
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
  print(1)
  localisations <- prepare_localisation_predictions(localisations, kriging_model$linear_regression)
  print(2)
  moose_st <- create_moose_st(localisations)
  print(3)
  predicted_res <- krige_residuals(kriging_model, moose_st, maxdist, nmax)
  print(4)
  pred_combined <- localisations$pred_lin + predicted_res
  print(5)
  final_prediction <- predict(kriging_model$power_transform, newdata = pred_combined, inverse = TRUE)
  
  return(final_prediction)
}

# Prepare start steps: these originally use t1_ and elevation_start.
prepare_start_steps <- function(df) {
  df <- df %>%
    mutate(
      x    = x1_,
      y    = y1_,
      day  = yday(t1_),
      time = t1_
    ) %>%
    arrange(time) %>%
    rename(elevation = elevation_start)
  df$gtt <- temp_geom(df$day, df$lat, variable = "mean")
  return(df)
}

# Prepare end steps: these originally use t2_ and elevation_end.
prepare_end_steps <- function(df) {
  df <- df %>%
    mutate(
      x    = x2_,
      y    = y2_,
      day  = yday(t2_),
      time = t2_
    ) %>%
    arrange(time) %>%
    rename(elevation = elevation_end)
  df$gtt <- temp_geom(df$day, df$lat, variable = "mean")
  return(df)
}
