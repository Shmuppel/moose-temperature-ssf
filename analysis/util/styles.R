library(colorspace)
library(ggplot2)

blue <- "#003147"
teal <- "#089099"
lightgreen <- "#E1F2E3"
green <- "#6CBA7D"
darkgreen <- "#06592A" 
beige <- "#D4B375"   
brown <- "#A67B3D" 
orange <- "#E88471"
red <- "#CF597E" 
purple <- "#7C1D6F"
grey <- "grey"
black <- "black"
mossgreen <- "#557A46"

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

landuse_legend_fill <- scale_fill_manual("Landuse",values = c(
  "Coniferous forest" = darkgreen,
  "Dedicious & mixed forest" = green,
  "Clear-cut & young forest" = beige,
  "Open" = grey,
  "Wetland" = red,
  "Water bodies" = teal,
  "Anthropogenic" = black,
  "Low mountain forest" = brown
), na.value="transparent", na.translate=F)

landuse_legend_fill <- scale_fill_manual(
  "Landuse",
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
