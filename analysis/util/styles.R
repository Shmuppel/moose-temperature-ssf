library(colorspace)
library(ggplot2)
library(sf)
library(geomtextpath) 

blue <- "#003147"
teal <- "#089099"
lightgreen <- "#9FE2B1"
green <- "#6CBA7D"
mossgreen <- "#557A46"
darkgreen <- "#06592A" 
beige <- "#D4B375"   
brown <- "#A67B3D" 
orange <- "#E88471"
red <- "#CF597E" 
purple <- "#7C1D6F"
grey <- "grey"
black <- "black"

greens_to_browns <- colorRampPalette(c(
  "#E2F3E4",  # off-mint
  "#8EBD8C",  # lichen
  "#5F8C61",  # sage
  "#927E71",  # aged wood 
  "#5A3E2B"   # dark bark
))

landuse_classes <- c(
  "Coniferous forest",
  "Dedicious & mixed forest",
  "Clear-cut & young forest",
  "Open",
  "Wetland",
  "Water bodies",
  "Anthropogenic",
  "Low mountain forest"
)

landuse_legend_fill <- scale_fill_manual("Land cover",values = c(
  "Coniferous forest" = darkgreen,
  "Dedicious & mixed forest" = green,
  "Clear-cut & young forest" = beige,
  "Open" = grey,
  "Wetland" = red,
  "Water bodies" = teal,
  "Anthropogenic" = black,
  "Low mountain forest" = brown
), na.value="transparent", na.translate=F)

landuse_legend_fill_numeric <- scale_fill_manual(
  "Land cover",
  values = c(
    "1"=darkgreen,
    "2"=green,
    "3"=beige,
    "4"=grey,
    "5"=red,
    "6"=teal,
    "7"=black
  ),
  na.value="transparent", 
  na.translate=F
)

harmonic_legend_color <- scale_color_manual(
  "Land cover",
  values = c(
    "Coniferous forest" = darkgreen,
    "Dedicious & mixed forest" = green,
    "Clear-cut & young forest" = beige,
    "Open" = grey,
    "Wetland" = red,
    "Water bodies" = teal,
    "Anthropogenic" = black,
    "Low mountain forest" = brown,
    
    "Elevation" = grey,
    "Distance to water" = teal,
    
    "Step length" = green,
    "Log step length" = darkgreen,
    "Cos turning angle" = "#927E71"
  ),
  na.value="transparent", 
  na.translate=F
)

# https://stackoverflow.com/questions/60016390/set-axes-limits-in-patchwork-when-combining-ggplot2-objects
apply_consistent_y_lims <- function(this_plot){
  num_plots <- length(this_plot$layers)
  y_lims <- lapply(1:num_plots, function(x) ggplot_build(this_plot[[x]])$layout$panel_scales_y[[1]]$range$range)
  min_y <- min(unlist(y_lims))
  max_y <- max(unlist(y_lims))
  this_plot & ylim(min_y, max_y)
}

# Assuming your basemap is already set up, we can add manual lines for the text paths
# Define rough text paths manually as sf LINESTRING objects
text_paths <- st_sf(
  label = c("boreal alpine", "boreal inland", "boreal coast", "temperate"),
  geometry = st_sfc(
    st_linestring(matrix(c(16, 68, 20, 67, 20, 66), ncol = 2, byrow = TRUE)),  # boreal alpine
    st_linestring(matrix(c(15, 65, 21, 64, 18, 63), ncol = 2, byrow = TRUE)),  # boreal inland
    st_linestring(matrix(c(21, 67, 25, 66, 23, 65), ncol = 2, byrow = TRUE)),  # boreal coast
    st_linestring(matrix(c(14, 58, 16, 57, 18, 56), ncol = 2, byrow = TRUE))   # temperate
  ),
  crs = 4326
)

strata_labels = geom_labelsf(
    data = text_paths,
    aes(geometry = geometry, label = label),
  )
