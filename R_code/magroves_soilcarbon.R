## Prediction of soil organic carbon stocks for world Mangroves at 30 m
## Training points (soil mangrove DB) by Kylen Solvik <ksolvik@whrc.org>
## Data processing by: Tom Hengl <tom.hengl@isric.org>, Jonathan Sanderman <jsanderman@whrc.org> and Greg Fiske <gfiske@whrc.org>

setwd("/data/mangroves")
load(".RData")
library(rgdal)
library(utils)
library(snowfall)
library(raster)
library(R.utils)
library(plotKML)
## RANGER connected packages (best install from github):
## speed up of computing of "se" in ranger https://github.com/imbs-hl/ranger/pull/231
#devtools::install_github("imbs-hl/ranger")
library(ranger)
#devtools::install_github("PhilippPro/quantregRanger")
library(quantregRanger)
## http://philipppro.github.io/Tuning_random_forest/
#devtools::install_github("PhilippPro/tuneRF")
library(tuneRF)

system("gdalinfo --version")
# GDAL 2.1.3, released 2017/20/01
system("saga_cmd --version")
# SAGA Version: 2.3.1
source('mangroves_soilcarbon_functions.R')

## List of tiles with mangroves ----
#system(paste0('saga_cmd shapes_grid 2 -GRIDS=\"MANGPRf_500m.sgrd\" -POLYGONS=\"/data/models/tiles_ll_100km.shp\" -PARALLELIZED=1 -RESULT=\"ov_mangrove_tiles.shp\"'))
#ov_mangroves = readOGR("ov_mangrove_tiles.shp", "ov_mangrove_tiles")
#str(ov_mangroves@data)
#summary(selS.t <- !ov_mangroves$MANGPRf_500.5==0)
## 1513 tiles with values
#ov_mangroves = ov_mangroves[selS.t,]
#saveRDS(ov_mangroves, "ov_mangroves.rds")
ov_mangroves = readRDS("ov_mangroves.rds")
plot(ov_mangroves)
writeOGR(ov_mangroves, "ov_mangroves.gpkg", "ov_mangroves", "GPKG")
tS.sel = as.character(ov_mangroves$ID)
newS.dirs <- paste0("/data/mangroves/tiled/T", tS.sel)
x <- lapply(newS.dirs, dir.create, recursive=TRUE, showWarnings=FALSE)

## rasterize polygons from Giri et al. WCMC-010-MangroveUSGS2011-ver1-3 ----
vrt = "/mnt/cartman/GlobalForestChange2000-2014/first.vrt"
landsat.r = raster(vrt)
tr = res(landsat.r)
#tr = c(0.00025, 0.00025)
#te = paste(unlist(ov_mangroves@data[100,c("xl","yl","xu","yu")]), collapse = " ")
#system(paste('gdal_rasterize ./DownloadPack-WCMC-010-MangroveUSGS2011-Ver1-3/WCMC-010-MangroveUSGS2011-ver1-3.shp', '-l WCMC-010-MangroveUSGS2011-ver1-3', '-te ', te, '-tr ', paste(tr, collapse=" "), ' -ot Byte', '-burn 100 MNGUSG_250m.tif -a_nodata 0 -co \"COMPRESS=DEFLATE\"'))
#tile_shape(1)
try( detach("package:snowfall", unload=TRUE), silent=TRUE)
try( detach("package:snow", unload=TRUE), silent=TRUE)
library(parallel)

cl <- parallel::makeCluster(54, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_shape(i)  ) } )
stopCluster(cl)
gc(); gc()

cl <- parallel::makeCluster(54, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_shape(i, tr=0.002083333, res.name="250m")  ) } )
stopCluster(cl)
gc(); gc()

#x = list.files("/data/mangroves/tiled", pattern=glob2rx("MNGUSG_30mf_T*.*"), full.names=TRUE, recursive=TRUE)
#unlink(x)

## Expand Giri map for 1 pixels ----
cl <- parallel::makeCluster(56, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( fill.NA.cells(i, tiles=ov_mangroves)  ) } )
stopCluster(cl)
gc(); gc()

## total clean-up (except for the mask map):
#xa = list.files("/data/mangroves/tiled", pattern=glob2rx("*.*"), full.names=TRUE, recursive=TRUE)
#x = list.files("/data/mangroves/tiled", pattern="MNGUSG", full.names=TRUE, recursive=TRUE)
#unlink(xa[-which(xa %in% x)])

#x = list.files("/data/mangroves/tiled", pattern=glob2rx("*L00*.tif"), full.names=TRUE, recursive=TRUE)
#xt = sapply(x, function(i){paste(file.info(i)$ctime)})
#sel = as.POSIXct(xt) < as.POSIXct("2017-03-07 17:05:00")
#unlink(x[sel])

## Global Forest Change (http://earthenginepartners.appspot.com/science-2013-global-forest/download_v1.2.html)
cl <- parallel::makeCluster(8, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i)  ) } )
stopCluster(cl)
gc(); gc()

cl <- parallel::makeCluster(8, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i, vrt="/mnt/cartman/GlobalForestChange2000-2014/last.vrt", name=c("REDL14","NIRL14","SW1L14","SW2L14"))  ) } )
stopCluster(cl)

cl <- parallel::makeCluster(8, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i, vrt="/mnt/cartman/GlobalForestChange2000-2014/treecover2000.vrt", name="TRCL00")  ) } )
stopCluster(cl)

## SRTM DEM (https://lta.cr.usgs.gov/SRTM1Arc)
cl <- parallel::makeCluster(8, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i, vrt="/mnt/cartman/SRTMGL1/SRTMGL1.2.tif", name="SRTMGL1", type="Int16", mvFlag=-32768)  ) } )
stopCluster(cl)

## Global Surface Water dynamics (https://global-surface-water.appspot.com/download)
cl <- parallel::makeCluster(8, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i, vrt="/mnt/cartman/GlobalSurfaceWater/occurrence.vrt", name="OCCGSW")  ) } )
stopCluster(cl)

cl <- parallel::makeCluster(8, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i, vrt="/mnt/cartman/GlobalSurfaceWater/extent.vrt", name="EXTGSW")  ) } )
stopCluster(cl)

## Tree cover 2010 (https://landcover.usgs.gov/glc/)
cl <- parallel::makeCluster(8, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i, vrt="/mnt/cartman/Landsat/treecover2010.vrt", name="TREL10")  ) } )
stopCluster(cl)

#del.lst = list.files("/data/mangroves/tiled", pattern="a2012mfw", full.names=TRUE, recursive=TRUE)
#unlink(del.lst)
## Hamilton's time series of Mangrove biomass loss -----
## https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/HKGBGS 
GDALinfo("a2012mfw.tif")
library(parallel)
cl <- parallel::makeCluster(48, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i, vrt="a2012mfw.tif", name="a2012mfw", fix.mask = FALSE, type = "Int16", mvFlag = "-32768")  ) } )
stopCluster(cl)

cl <- parallel::makeCluster(48, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_tif(i, vrt="a2000mfw.tif", name="a2000mfw", fix.mask = FALSE, type = "Int16", mvFlag = "-32768")  ) } )
stopCluster(cl)


library(parallel)
cl <- parallel::makeCluster(48, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( system(paste0('gdal_translate /data/mangroves/tiled/T', ov_mangroves@data[i,"ID"], '/MNGUSG_30mf_T', ov_mangroves@data[i,"ID"], '.tif /data/mangroves/tiled/T', ov_mangroves@data[i,"ID"], '/MNGUSG_30mf_T', ov_mangroves@data[i,"ID"], '.sdat -of \"SAGA\"')) ) } )
stopCluster(cl)

library(parallel)
cl <- parallel::makeCluster(48, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( system(paste0('gdal_translate /data/mangroves/tiled/T', ov_mangroves@data[i,"ID"], '/MNGUSG_250m_T', ov_mangroves@data[i,"ID"], '.tif /data/mangroves/tiled/T', ov_mangroves@data[i,"ID"], '/MNGUSG_250m_T', ov_mangroves@data[i,"ID"], '.sdat -of \"SAGA\"')) ) } )
stopCluster(cl)

## Globally predicted OCD using SoilGrids250m ---- 

#del.lst = list.files("/data/mangroves/tiled", pattern="SOCS_0_200cm_30m", full.names=TRUE, recursive=TRUE)
#unlink(del.lst)
#downscale_tif(i=which(ov_mangroves$ID=="31419"), vrt="/data/GEOG/OCSTHA_M_200cm_250m_ll.tif", name="SOCS_0_200cm", tiles=ov_mangroves)

library(snowfall)
sfInit(parallel=TRUE, cpus=24)
sfExport("downscale_tif", "ov_mangroves")
sfLibrary(rgdal)
sfLibrary(RSAGA)
out <- sfClusterApplyLB(1:nrow(ov_mangroves), function(i){ try( downscale_tif(i, vrt="/data/GEOG/OCSTHA_M_200cm_250m_ll.tif", name="SOCS_0_200cm", tiles=ov_mangroves, cpus=1) )})
sfStop()

#del.lst = list.files("/data/mangroves/tiled", pattern="SST_", full.names=TRUE, recursive=TRUE)
#unlink(del.lst)

#del.lst = list.files("/data/mangroves/tiled", pattern="SST_", full.names=TRUE, recursive=TRUE)
#unlink(del.lst)
## Sea surface temperature ----
## https://neo.sci.gsfc.nasa.gov/view.php?datasetId=MYD28M 
## average per season
meanf <- function(x){calc(x, mean, na.rm=TRUE)}
m.lst = list(1:3,4:6,7:9,10:12)
for(j in 1:4){
  if(!file.exists(paste0("./SurfaceTemp/sst_season_",j,".tif"))){
    sD = paste0("./SurfaceTemp/sst_monthly_mean_", m.lst[[j]],".tif")
    beginCluster()
    r1 <- clusterR(raster::stack(sD), fun=meanf, filename=paste0("./SurfaceTemp/sst_season_",j,".tif"), datatype="INT2S", options=c("COMPRESS=DEFLATE"))
    endCluster()
  }
}

## fill in gaps (land mask)
## this was not trivial because input layers had coordinates messed up
## TAKES >4 hrs to run
for(j in 1:4){
  if(!file.exists(paste0('./SurfaceTemp/sst_season_', j, '_f.tif'))){
    tmp.file1 = paste0(tempfile(), ".sdat")
    tmp.file2 = paste0(tempfile(), ".sdat")
    x = readGDAL(paste0('./SurfaceTemp/sst_season_', j, '.tif'))
    writeGDAL(x, tmp.file1, drivername = "SAGA", mvFlag = -32767, type = "Int16")
    system(paste0('saga_cmd -c=55 grid_tools 7 -THRESHOLD .05 -INPUT ', RSAGA::set.file.extension(tmp.file1, ".sgrd"), ' -RESULT ', RSAGA::set.file.extension(tmp.file2, ".sgrd")))
    x0 = readGDAL(tmp.file2)
    x0@grid = x@grid
    writeGDAL(x0, paste0('./SurfaceTemp/sst_season_', j, '_f.tif'), type = "Int16", options = c("COMPRESS=DEFLATE"), mvFlag = -32768)
  }
}

## downscale to 30 m resolution:
for(j in c(1:4)){
  library(snowfall)
  sfInit(parallel=TRUE, cpus=55)
  sfExport("downscale_tif", "ov_mangroves", "j")
  sfLibrary(rgdal)
  sfLibrary(RSAGA)
  out <- sfClusterApplyLB(1:nrow(ov_mangroves), function(i){ try( downscale_tif(i, vrt=paste0("/data/mangroves/SurfaceTemp/sst_season_", j,"_f.tif"), name=paste0("SST_", j), tiles=ov_mangroves, cpus=1, fill.gaps.method="resampling") )})
  sfStop()
}

#del.lst = list.files("/data/mangroves/tiled", pattern="TidalRange_", full.names=TRUE, recursive=TRUE)
#unlink(del.lst)
## Tidal range ----
tmp.file1 = paste0(tempfile(), ".sdat")
tmp.file2 = paste0(tempfile(), ".sdat")
x = readGDAL('./TidalRange/amplitude_Layer.tif')
x$band1 = x$band1*100
writeGDAL(x, tmp.file1, drivername = "SAGA", mvFlag = -32767, type = "Int16")
system(paste0('saga_cmd -c=55 grid_tools 7 -THRESHOLD .05 -INPUT ', RSAGA::set.file.extension(tmp.file1, ".sgrd"), ' -RESULT ', RSAGA::set.file.extension(tmp.file2, ".sgrd")))
x0 = readGDAL(tmp.file2)
x0@grid = x@grid
writeGDAL(x0, './TidalRange/amplitude_Layer_f.tif', type = "Int16", options = c("COMPRESS=DEFLATE"), mvFlag = -32768)

library(snowfall)
sfInit(parallel=TRUE, cpus=55)
sfExport("downscale_tif", "ov_mangroves")
sfLibrary(rgdal)
sfLibrary(RSAGA)
out <- sfClusterApplyLB(1:nrow(ov_mangroves), function(i){ try( downscale_tif(i, vrt="/data/mangroves/TidalRange/amplitude_Layer_f.tif", name="TidalRange", tiles=ov_mangroves, cpus=1, fill.gaps.method="spline") )})
sfStop()

## TSM data ----
#del.lst = list.files("/data/mangroves/tiled", pattern="TSM_", full.names=TRUE, recursive=TRUE)
#unlink(del.lst)
meanf100 <- function(x){100*calc(x, mean, na.rm=TRUE)}
m.lst = list(paste0(0,1:3),paste0(0,4:6),paste0(0,7:9),10:12)
for(j in 1:4){
  if(!file.exists(paste0("./TSM_data/TSM_",j,".tif"))){
    sD = paste0("./TSM_data/longTermMeans/mean", m.lst[[j]],"_comp.tif")
    beginCluster()
    r1 <- clusterR(raster::stack(sD), fun=meanf100, filename=paste0("./TSM_data/TSM_0",j,".tif"), datatype="INT2S", options=c("COMPRESS=DEFLATE"))
    endCluster()
  }
}

## Convert values to integers and filter missing values:
tsm.lst = list.files("./TSM_data", ".tif", full.names = TRUE)
for(j in tsm.lst){
  if(!file.exists(gsub(".tif", "_f.tif", j))){
    tmp.file1 = paste0(tempfile(), ".sdat")
    tmp.file2 = paste0(tempfile(), ".sdat")
    #tmp.file1 = paste0(tempfile(), ".tif")
    #tmp.file2 = paste0(tempfile(), ".tif")
    x = readGDAL(j)
    writeGDAL(x, tmp.file1, drivername = "SAGA", mvFlag = -32767, type = "Int16")
    #writeGDAL(x, tmp.file1, mvFlag = -32767, type = "Int16", options = c("COMPRESS=DEFLATE"))
    #system(paste0('saga_cmd -c=55 grid_tools 25 -RADIUS 30 -MAXPOINTS 100 -GRID ', RSAGA::set.file.extension(tmp.file1, ".sgrd"), ' -CLOSED ', RSAGA::set.file.extension(tmp.file2, ".sgrd")))
    #system(paste0('gdal_fillnodata.py -md 100 -si 5 ', tmp.file1, ' ', tmp.file2))
    ## TAKES >6 hours!
    system(paste0('saga_cmd -c=55 grid_tools 7 -THRESHOLD .05 -INPUT ', RSAGA::set.file.extension(tmp.file1, ".sgrd"), ' -RESULT ', RSAGA::set.file.extension(tmp.file2, ".sgrd")))
    x0 = readGDAL(tmp.file2)
    x0@grid = x@grid
    writeGDAL(x0, gsub(".tif", "_f.tif", j), type = "Int16", options = c("COMPRESS=DEFLATE"), mvFlag = -32768)
    unlink(tmp.file1); unlink(tmp.file2)
  }
}

#del.lst = list.files("/data/mangroves/tiled", pattern="TSM_", full.names=TRUE, recursive=TRUE)
#unlink(del.lst)
## downscale to 30 m resolution:
tsm_f.lst = list.files("./TSM_data", pattern=glob2rx("TSM_*_f.tif$"), full.names = TRUE)
for(j in 1:length(tsm_f.lst)){
  library(snowfall)
  sfInit(parallel=TRUE, cpus=24)
  sfExport("downscale_tif", "ov_mangroves", "j", "tsm_f.lst")
  sfLibrary(rgdal)
  sfLibrary(RSAGA)
  out <- sfClusterApplyLB(1:nrow(ov_mangroves), function(i){ try( downscale_tif(i, vrt=tsm_f.lst[j], name=paste0("TSM_", j), tiles=ov_mangroves, cpus=1, fill.gaps.method="spline"), silent = TRUE)})
  sfStop()
}

## Mangrove topology ----
unzip("/data/mangroves/mangrove_typology/mangrove typology.zip")
mtype = readOGR("Mangrove_typology_final.shp", "Mangrove_typology_final")
# OGR data source with driver: ESRI Shapefile 
# Source: "Mangrove_typology_final.shp", layer: "Mangrove_typology_final"
# with 1408398 features
# It has 9 fields
levels(mtype$Typology)
summary(mtype$Typology)
# Estuarine Mineralogenic   Organogenic 
# 973883        351284         83231
#mtype = spTransform(mtype, CRS("+proj=longlat +datum=WGS84"))
mtype1 = mtype[mtype$Typology=="Estuarine",]
mtype2 = mtype[mtype$Typology=="Mineralogenic",]
mtype3 = mtype[mtype$Typology=="Organogenic",]
writeOGR(mtype1["Typology"], "Mangrove_typology_Estuarine.shp", "Mangrove_typology_Estuarine", "ESRI Shapefile")
system('ogr2ogr -t_srs EPSG:4326 Mangrove_typology_Estuarine_ll.shp Mangrove_typology_Estuarine.shp')
writeOGR(mtype2["Typology"], "Mangrove_typology_Mineralogenic.shp", "Mangrove_typology_Mineralogenic", "ESRI Shapefile")
system('ogr2ogr -t_srs EPSG:4326 Mangrove_typology_Mineralogenic_ll.shp Mangrove_typology_Mineralogenic.shp')
writeOGR(mtype3["Typology"], "Mangrove_typology_Organogenic.shp", "Mangrove_typology_Organogenic", "ESRI Shapefile")
system('ogr2ogr -t_srs EPSG:4326 Mangrove_typology_Organogenic_ll.shp Mangrove_typology_Organogenic.shp')
rm(mtype); rm(mtype1); rm(mtype2); rm(mtype3)
gc(); gc(); save.image()

## Test it:
#tile_shape(i=which(ov_mangroves$ID=="31419"), shape="Mangrove_typology_Estuarine_ll.shp", l="Mangrove_typology_Estuarine_ll", varname="MTYP_Estuarine")
#tile_shape(i=which(ov_mangroves$ID=="31419"), shape="Mangrove_typology_Mineralogenic_ll.shp", l="Mangrove_typology_Mineralogenic_ll", varname="MTYP_Mineralogenic")
#tile_shape(i=which(ov_mangroves$ID=="31419"), shape="Mangrove_typology_Organogenic_ll.shp", l="Mangrove_typology_Organogenic_ll", varname="MTYP_Organogenic")

try( detach("package:snowfall", unload=TRUE), silent=TRUE)
try( detach("package:snow", unload=TRUE), silent=TRUE)
library(parallel)
cl <- parallel::makeCluster(24, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_shape(i, shape="Mangrove_typology_Estuarine_ll.shp", l="Mangrove_typology_Estuarine_ll", varname="MTYP_Estuarine")  ) } )
stopCluster(cl)
cl <- parallel::makeCluster(24, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_shape(i, shape="Mangrove_typology_Mineralogenic_ll.shp", l="Mangrove_typology_Mineralogenic_ll", varname="MTYP_Mineralogenic")  ) } )
stopCluster(cl)
cl <- parallel::makeCluster(24, type="FORK")
x = parLapply(cl, 1:nrow(ov_mangroves@data), fun=function(i){ try( tile_shape(i, shape="Mangrove_typology_Organogenic_ll.shp", l="Mangrove_typology_Organogenic_ll", varname="MTYP_Organogenic")  ) } )
stopCluster(cl)
gc(); gc()

## Soil profiles (soil profile Mangrove DB) ----
## https://docs.google.com/spreadsheets/d/1xVh1cxH1l9cVpKqbqh3Vzx7iqRq3gvne-mMiqm7QVn4/edit#gid=944439000
profs <- read.csv("mangrove_soc_database_v10_sites.csv")
summary(is.na(profs$Latitude_Adjusted))
profs.f <- plyr::rename(profs, c("Site.name"="SOURCEID", "Longitude_Adjusted"="LONWGS84", "Latitude_Adjusted"="LATWGS84"))
profs.f$TIMESTRR <- as.Date(profs.f$Years_collected, format="%Y")
profs.f$SOURCEDB = "MangrovesDB"
profs.f$LONWGS84 = as.numeric(paste(profs.f$LONWGS84))
profs.f$LATWGS84 = as.numeric(paste(profs.f$LATWGS84))
str(profs.f)
## 'data.frame':	1812 obs. of  32 variables
length(levels(unique(as.factor(paste0("ID", profs.f$LONWGS84, profs.f$LATWGS84, sep="_")))))
## 1667
hors <- read.csv("mangrove_soc_database_v10_horizons.csv")
hors.f <- plyr::rename(hors, c("Site.name"="SOURCEID", "U_depth"="UHDICM", "L_depth"="LHDICM", "OC_final"="ORCDRC", "BD_final"="BLD"))
hors.f$ORCDRC <- hors.f$ORCDRC*10
hors.f$BLD.f <- hors.f$BLD*1000
## convert depths to cm:
hors.f$UHDICM = hors.f$UHDICM*100
hors.f$LHDICM = hors.f$LHDICM*100
summary(hors.f$CD_calc)
hors.f$OCDENS = hors.f$CD_calc * 1000
hors.f$DEPTH <- hors.f$UHDICM + (hors.f$LHDICM - hors.f$UHDICM)/2
hors.fs = hor2xyd(hors.f)
## 14780 values now
SPROPS.MangrovesDB <- plyr::join(profs.f[,c("SOURCEID","SOURCEDB","TIMESTRR","LONWGS84","LATWGS84")], hors.fs[,c("SOURCEID","UHDICM","LHDICM","DEPTH","BLD.f","ORCDRC","OCDENS")])
SPROPS.MangrovesDB = SPROPS.MangrovesDB[!is.na(SPROPS.MangrovesDB$LONWGS84) & !is.na(SPROPS.MangrovesDB$LATWGS84) & !is.na(SPROPS.MangrovesDB$DEPTH),]
SPROPS.MangrovesDB = SPROPS.MangrovesDB[!SPROPS.MangrovesDB$DEPTH>1000,]
str(SPROPS.MangrovesDB)
## 'data.frame':	14356 obs. of  11 variables
#hist(SPROPS.MangrovesDB$DEPTH)

coordinates(SPROPS.MangrovesDB) = ~LONWGS84+LATWGS84
proj4string(SPROPS.MangrovesDB) = CRS("+proj=longlat +datum=WGS84")
#View(SPROPS.MangrovesDB@data)
SPROPS.MangrovesDB$LOC_ID = as.factor(paste0("ID", SPROPS.MangrovesDB@coords[,1], SPROPS.MangrovesDB@coords[,2], sep="_"))
length(levels(unique(SPROPS.MangrovesDB$LOC_ID)))
## 1595 profiles in total
unlink("mangroves_SOC_points.gpkg")
writeOGR(SPROPS.MangrovesDB, "mangroves_SOC_points.gpkg", "mangroves_SOC_points", "GPKG")
summary(as.factor(SPROPS.MangrovesDB$SOURCEDB))
plot(SPROPS.MangrovesDB)


## prepare tiles for overlay / prediction ----
in.covs = c("MNGUSG_30mf", "SOCS_0_200cm_30m", "a2000mfw_30m", "a2012mfw_30m", "TREL10_30m", "TRCL00_30m", "SW1L14_30m", "SW2L14_30m", "SW1L00_30m", "SW2L00_30m", "SRTMGL1_30m", "REDL14_30m", "REDL00_30m", "OCCGSW_30m", "NIRL14_30m", "EXTGSW_30m", "NIRL00_30m", paste0("SST_",c(1:4),"_30m"), paste0("TSM_",c(1:4),"_30m"), "TidalRange_30m", paste0("MTYP_",c("Organogenic","Mineralogenic","Estuarine"), "_30m"))
## 29 layers

#del.lst = list.files("/data/mangroves/tiled", pattern=glob2rx("T*.rds$"), full.names=TRUE, recursive=TRUE)
#unlink(del.lst)
new_data(i=which(ov_mangroves$ID=="28356"), in.covs, tiles=ov_mangroves)
#m = readRDS("/data/mangroves/tiled/T28356/T28356.rds")

## takes ca 2 hrs...
library(snowfall)
snowfall::sfInit(parallel=TRUE, cpus=24)
snowfall::sfLibrary(rgdal)
snowfall::sfLibrary(raster)
snowfall::sfExport("new_data", "ov_mangroves", "in.covs")
out <- snowfall::sfClusterApplyLB(1:nrow(ov_mangroves), function(i){ new_data(i, in.covs, tiles=ov_mangroves) })
snowfall::sfStop()
## Error in checkForRemoteErrors(val) : 
## 2 nodes produced errors; first error: NAs not permitted in row index

## Overlay points and 30 m res covs ----
#tile.pol = rgdal::readOGR("/data/models/tiles_ll_100km.shp", "tiles_ll_100km")
source("/data/models/extract_tiled.R")
ovM <- extract.tiled(x=SPROPS.MangrovesDB, tile.pol=tile.pol, path="/data/mangroves/tiled", ID="ID", cpus=56)
rmatrix = ovM[,c("SOURCEID","DEPTH","OCDENS",in.covs)]
names(rmatrix) = gsub("L00_30m", "_30m", names(rmatrix))
names(rmatrix) = gsub("a2000mfw_30m", "mfw_30m", names(rmatrix))
str(rmatrix)
## 'data.frame':	7940 obs. of  32 variables
summary(rmatrix$OCDENS)
summary(rmatrix$SOCS_0_200cm_30m)
summary(rmatrix$MTYP_Organogenic_30m)
summary(rmatrix$SST_3_30m)
summary(rmatrix$TidalRange_30m)
summary(rmatrix$MNGUSG_30m)
## 1195 missing values

## Fit a ranger model ----
library(quantregRanger)
fm.OCDENS <- as.formula(paste0("OCDENS ~ DEPTH + SOCS_0_200cm_30m + TRC_30m + SW1_30m + SW2_30m + SRTMGL1_30m + RED_30m + NIR_30m +", paste0("SST_",c(1:4),"_30m", collapse="+"), "+", paste0("TSM_",c(1:4),"_30m", collapse="+"), "+", paste0("MTYP_",c("Organogenic","Mineralogenic","Estuarine"), "_30m", collapse = "+"), "+ TidalRange_30m"))
fm.OCDENS
## Note: banding artifacts in TSM_3 to TSM_5
rmatrix.f = rmatrix[complete.cases(rmatrix[,all.vars(fm.OCDENS)]),]
library(tuneRF)
rt.OCDENS <- makeRegrTask(data = rmatrix.f[,all.vars(fm.OCDENS)], target = "OCDENS")
estimateTimeTuneRF(rt.OCDENS)
## 2-3 mins
t.OCDENS <- tuneRF(rt.OCDENS, num.trees = 150, build.final.model = FALSE)
t.OCDENS
pars.OCDENS = list(mtry=t.OCDENS$recommended.pars$mtry, min.node.size=t.OCDENS$recommended.pars$min.node.size, sample.fraction=t.OCDENS$recommended.pars$sample.fraction, num.trees=150)
m.OCDENSq_30m <- quantregRanger(fm.OCDENS, rmatrix.f, pars.OCDENS)
m.OCDENS_30m <- ranger(fm.OCDENS, rmatrix.f, num.trees = 150, importance='impurity', mtry= t.OCDENS$recommended.pars$mtry, min.node.size=t.OCDENS$recommended.pars$min.node.size, sample.fraction=t.OCDENS$recommended.pars$sample.fraction)
m.OCDENS_30m
# Type:                             Regression 
# Number of trees:                  150 
# Sample size:                      12240 
# Number of independent variables:  20 
# Mtry:                             11 
# Target node size:                 2 
# Variable importance mode:         impurity 
# OOB prediction error (MSE):       47.87222 
# R squared (OOB):                  0.8433812
# RMSE = +/- 6.9 kg/m3
xl <- as.list(ranger::importance(m.OCDENS_30m))
#xl <- as.list(m.OCDENSq_30m$variable.importance)
print(t(data.frame(xl[order(unlist(xl), decreasing=TRUE)[1:10]])))
# SOCS_0_200cm_30m 1270690.46
# DEPTH             227007.42
# TSM_2_30m         147169.00
# TRC_30m           144498.64
# TSM_1_30m         122826.39
# TSM_3_30m         109609.18
# RED_30m            89163.26
# TidalRange_30m     78975.45
# SST_1_30m          54062.01
# SST_3_30m          53916.74

## LLO Cross-validation of the ranger model ----
cv.m.OCDENS_30m = cv_numeric(formulaString = fm.OCDENS, rmatrix = rmatrix.f, idcol="SOURCEID", nfold=5, cpus=1, pars.ranger = pars.OCDENS)
cv.m.OCDENS_30m$Summary
## R-square 0.63
## plot results of fitting and CV next to each other:
pfun <- function(x,y, ...){
  panel.hexbinplot(x,y, ...)  
  panel.abline(0,1,lty=1,lw=2,col="black")
}
library(hexbin)
library(lattice)
library(scales)
library(gridExtra)

pdf(file = "Fig_correlation_plots_RF_OCD_mangroves.pdf", width=14.4, height=8)
par(oma=c(0,0,0,1), mar=c(0,0,0,2))
plt.RF = hexbinplot(rmatrix.f$OCDENS~m.OCDENS_30m$predictions, colramp=colorRampPalette(SAGA_pal[[1]][8:20]), main=paste0("Model fitting OCD (kg/m-cubic); N = ", length(m.OCDENS_30m$predictions)), ylab="measured", xlab="predicted (machine learning)", type="g", lwd=1, lcex=8, inner=.4, cex.labels=1, xbins=40, asp=1, xlim=c(0,100), ylim=c(0,100), colorcut=c(0,0.005,0.01,0.03,0.07,0.15,0.25,0.5,1), panel=pfun)
plt.CV = hexbinplot(cv.m.OCDENS_30m$CV_residuals$Observed~cv.m.OCDENS_30m$CV_residuals$Predicted, colramp=colorRampPalette(SAGA_pal[[1]][8:20]), main=paste0("Cross-Validation OCD (kg/m-cubic); N = ", length(cv.m.OCDENS_30m$CV_residuals$Observed)), ylab="measured", xlab="predicted (machine learning)", type="g", lwd=1, lcex=8, inner=.4, cex.labels=1, xbins=28, asp=1, xlim=c(0,100), ylim=c(0,100), colorcut=c(0,0.005,0.01,0.03,0.07,0.15,0.25,0.5,1), panel=pfun)
grid.arrange(plt.RF, plt.CV, ncol=2)
dev.off()

## Variable importance plot:
xlt = t(data.frame(xl[order(unlist(xl), decreasing=TRUE)[1:20]]))
pdf(file = "Fig_ranger_importance_plot_100cm.pdf", width = 7, height = 7.5)
#png(file = "Fig_ranger_importance_plot_100cm.png", width = 7, height = 7.5)
par(mar=c(2.5,9,2.5,0.5), oma=c(1,1,1,1))
plot(x=rev(xlt)/max(xlt)*100, y=1:20, pch = 19, col="blue", xlab="Importance (%)", xlim=c(0,105), ylim=c(0,21), yaxp=c(0,20,20), xaxs="i", yaxs="i", cex=1.4, yaxt="n", ylab="", main="OCD model importance plot", cex.main=1)
abline(h=1:20, lty=2, col="grey")
#axis(2, at=1:20, labels=rev(attr(xlt, "dimnames")[[1]]), las=2)
axis(2, at=1:20, labels=rev(c(expression(bold("SoilGrids OCS")), "Soil depth", "TSM 2", "Tree cover", "TSM 1", "TSM 3", "Landsat red", "Tidal range", "SST 1", "SST 3", "SST 2", "TSM 4", "SST 4", "SRTM DEM", "Landsat SW1", "Landsat NIR",  "Landsat SW2", "Organogenic", "Mineralogenic", "Estuarine")), las=2)
#axis(2, at=1:20, labels=rev(c(expression(bold("SoilGrids OCS")), "Tree cover", "Soil depth", "TSM 3", "TMS 12", "TSM 5", "TSM 4", "TSM 1", "TSM 9", "Landsat red", "SST 1", "TSM 11", "Tidal range", "TMS 10", "SST 4", "SST 3", "TSM 7", "SST 2", "Landsat SW2", "TSM 2", "TSM 8", "Landsat SW1", "Landsat NIR", "TSM 6", "SRTM DEM",  "Organogenic", "Mineralogenic", "Estuarine")), las=2)
dev.off()
rmatrix.f$OCDENS.predicted = m.OCDENS_30m$predictions
write.csv(rmatrix.f, file="rmatrix_OCD.csv")

## Spatially-balanced RF (subset points so that areas with very dense points are not over-represented)
# library(randomForest)
# m.OCDENS_30m.lst = NULL
# for(i in 1:5){
#   spBL = GSIF::sample.grid(SPROPS.MangrovesDB[!duplicated(SPROPS.MangrovesDB$LOC_ID),"SOURCEID"], cell.size = c(0.2,0.2), n = 2)
#   data.t = rmatrix[rmatrix$SOURCEID %in% paste(spBL$subset$SOURCEID),]
#   data.t = data.t[complete.cases(data.t[,all.vars(fm.OCDENS)]),]
#   #m.OCDENS_30m.lst[[i]] = ranger(fm.OCDENS, data.t, num.trees = 85)
#   m.OCDENS_30m.lst[[i]] = randomForest(data.t[,all.vars(fm.OCDENS)[-1]], data.t[,all.vars(fm.OCDENS)[1]], ntree = 85)
# }
# ## Bind all models together:
# gm = do.call(randomForest::combine, m.OCDENS_30m.lst)

## test model without SoilGrids:
fm.OCDENS0 <- as.formula(paste0("OCDENS ~ DEPTH + TRC_30m + SW1_30m + SW2_30m + SRTMGL1_30m + RED_30m + NIR_30m +", paste0("SST_",c(1:4),"_30m", collapse="+"), "+", paste0("TSM_",c(1:4),"_30m", collapse="+"), "+", paste0("MTYP_",c("Organogenic","Mineralogenic","Estuarine"), "_30m", collapse = "+"), "+ TidalRange_30m"))
m.OCDENS0_30m <- ranger(fm.OCDENS0, rmatrix[complete.cases(rmatrix[,all.vars(fm.OCDENS0)]),], num.trees = 150, importance='impurity')
m.OCDENS0_30m
# OOB prediction error (MSE):       53.2236
# R squared (OOB):                  0.8258736
xl0 <- as.list(ranger::importance(m.OCDENS0_30m))
print(t(data.frame(xl0[order(unlist(xl0), decreasing=TRUE)[1:10]])))
cv.m.OCDENS0_30m = cv_numeric(formulaString = fm.OCDENS0, rmatrix = rmatrix.f, idcol="SOURCEID", nfold=5, cpus=1, pars.ranger = pars.OCDENS)
cv.m.OCDENS0_30m$Summary

## clean up:
#del.lst = list.files("/data/mangroves/tiled", pattern=glob2rx("OCDENS_*.tif$"), full.names=TRUE, recursive=TRUE)
#unlink(del.lst)
#del.lst = list.files("/data/mangroves/tiled", pattern=glob2rx("dSOCS_0_100cm_*.tif$"), full.names=TRUE, recursive=TRUE)
#unlink(del.lst)

## Predictions ----
#predict_x(i=which(ov_mangroves$ID=="31419"), tiles=ov_mangroves, gm=m.OCDENS_30m)
#predict_x(i=which(ov_mangroves$ID=="31420"), tiles=ov_mangroves, gm=m.OCDENS_30m)
#predict_x(i=which(ov_mangroves$ID=="24778"), tiles=ov_mangroves, gm=m.OCDENS_30m)
#predict_x(i=which(ov_mangroves$ID=="26085"), tiles=ov_mangroves, gm=m.OCDENS_30m)

library(parallel)
library(rgdal)
library(ranger)
library(plyr)
cl <- parallel::makeCluster(14, type="FORK")
x = parallel::parLapply(cl, 1:nrow(ov_mangroves), fun=function(i){ try( predict_x(i, tiles=ov_mangroves, gm=m.OCDENS_30m) ) } )
stopCluster(cl)
#try( detach("package:parallel", unload=TRUE), silent=TRUE)
closeAllConnections()

## global mosaics at 100 m (takes >5 hrs to produce):
tmp.lst <- list.files(path="./tiled", pattern=glob2rx("dSOCS_0_100cm_year2000_*.tif$"), full.names=TRUE, recursive=TRUE)
out.tmp <- tempfile(fileext = ".txt")
vrt.tmp <- tempfile(fileext = ".vrt")
cat(tmp.lst, sep="\n", file=out.tmp)
system(paste0('gdalbuildvrt -input_file_list ', out.tmp, ' ', vrt.tmp))
unlink("Mangroves_SOCS_0_100cm_100m.tif")
system(paste0('gdalwarp ', vrt.tmp, ' Mangroves_SOCS_0_100cm_100m.tif -co \"COMPRESS=DEFLATE\" -co \"BIGTIFF=YES\" -wm 2000 -r \"average" -tr 0.001 0.001 -te -180 -39 180 33 -multi -wo \"NUM_THREADS=ALL_CPUS\" --config GDAL_CACHEMAX 2000'))
GDALinfo("Mangroves_SOCS_0_100cm_100m.tif")
#unlink("Mangroves_SOCS_0_100cm_30m.tif")
#system(paste0('gdalwarp ', vrt.tmp, ' Mangroves_SOCS_0_100cm_30m.tif -co \"COMPRESS=DEFLATE\" -co \"BIGTIFF=YES\" -wm 2000 -r \"near\" -tr 0.0003 0.0003 -te -180 -39 180 33'))

tmp2.lst <- list.files(path="./tiled", pattern=glob2rx("dSOCS_0_200cm_year2000_*.tif$"), full.names=TRUE, recursive=TRUE)
out.tmp <- tempfile(fileext = ".txt")
vrt.tmp <- tempfile(fileext = ".vrt")
cat(tmp2.lst, sep="\n", file=out.tmp)
system(paste0('gdalbuildvrt -input_file_list ', out.tmp, ' ', vrt.tmp))
unlink("Mangroves_SOCS_0_200cm_100m.tif")
system(paste0('gdalwarp ', vrt.tmp, ' Mangroves_SOCS_0_200cm_100m.tif -co \"COMPRESS=DEFLATE\" -co \"BIGTIFF=YES\" -wm 2000 -r \"average" -tr 0.001 0.001 -te -180 -39 180 33 -multi -wo \"NUM_THREADS=ALL_CPUS\" --config GDAL_CACHEMAX 2000'))

## compress all files to one file:
unlink("Mangroves_SOCS_0_100cm_30m.zip"); unlink("Mangroves_SOCS_0_200cm_30m.zip")
zip(zipfile="Mangroves_SOCS_0_100cm_30m.zip", files=tmp.lst)
zip(zipfile="Mangroves_SOCS_0_200cm_30m.zip", files=tmp2.lst)

## Random sample for the purpose of PCA / uncertainty assessment:
n.smp = round(2e4/nrow(ov_mangroves)*80) ## about 20,000 randomly allocated points
r.pnt <- parallel::mclapply(ov_mangroves@polygons, function(i){as.data.frame(spsample(x = i, n = n.smp, type = "random"))}, mc.cores = 24)
r.pnt <- do.call(rbind, r.pnt)
r.pnt$ID = paste("ID", r.pnt$x, r.pnt$y, sep="_")
coordinates(r.pnt) = ~ x+y
proj4string(r.pnt) = ov_mangroves@proj4string
## takes >20 mins
library(snowfall)
ovR <- extract.tiled(x=r.pnt, tile.pol=tile.pol, path="/data/mangroves/tiled", ID="ID", cpus=24)
pca.matrix = ovR[!is.na(ovR$TREL10_30m),]
names(pca.matrix) = gsub("L00_30m", "_30m", names(pca.matrix))
names(pca.matrix) = gsub("a2000mfw_30m", "mfw_30m", names(pca.matrix))
## Predict upper lower limits:
for(i in c(0,30,100,200)){
  pca.matrix$DEPTH = i
  #pre.r = predict(m.OCDENSq_30m, data=pca.matrix, quantiles=c(0.025,0.5,0.975))
  ## 1 standard deviation:
  pre.r = predict(m.OCDENSq_30m, data=pca.matrix, quantiles=c((1-.682)/2, 0.5, 1-(1-.682)/2))
  pca.matrix[,paste0("OCDENS_M_",i)] = pre.r[,2]*10
  pca.matrix[,paste0("OCDENS_L_",i)] = ifelse(pre.r[,1]<0, 0, pre.r[,1])*10
  pca.matrix[,paste0("OCDENS_U_",i)] = pre.r[,3]*10
  pca.matrix[,paste0("OCDENS_sd_",i)] = (pre.r[,3]-pre.r[,1])/2*10
}
pca.matrix$DEPTH = NULL
gc(); gc()

## Standard errors of OCS 0-100 cm ----
pca.matrix$OCDENS_M_0_30cm = rowMeans(pca.matrix[,c("OCDENS_M_0", "OCDENS_M_30")], na.rm=TRUE)*30/100
pca.matrix$OCDENS_M_30_100cm = rowMeans(pca.matrix[,c("OCDENS_M_30", "OCDENS_M_100")], na.rm=TRUE)*70/100
pca.matrix$dSOCS_0_100cm_year2000 = rowSums(pca.matrix[,c("OCDENS_M_0_30cm", "OCDENS_M_30_100cm")], na.rm=TRUE)
summary(pca.matrix$dSOCS_0_100cm_year2000)
## Errors of OCS
pca.matrix$OCDENS_U_0_30cm = rowMeans(pca.matrix[,c("OCDENS_U_0", "OCDENS_U_30")], na.rm=TRUE)*30/100 
pca.matrix$OCDENS_U_30_100cm = rowMeans(pca.matrix[,c("OCDENS_U_30", "OCDENS_U_100")], na.rm=TRUE)*70/100
pca.matrix$OCDENS_L_0_30cm = rowMeans(pca.matrix[,c("OCDENS_L_0", "OCDENS_L_30")], na.rm=TRUE)*30/100 
pca.matrix$OCDENS_L_30_100cm = rowMeans(pca.matrix[,c("OCDENS_L_30", "OCDENS_L_100")], na.rm=TRUE)*70/100
pca.matrix$dSOCS_sd_0_100cm_year2000 = (rowSums(pca.matrix[,c("OCDENS_U_0_30cm", "OCDENS_U_30_100cm")], na.rm=TRUE) - rowSums(pca.matrix[,c("OCDENS_L_0_30cm", "OCDENS_L_30_100cm")], na.rm=TRUE))/2
summary(pca.matrix$dSOCS_sd_0_100cm_year2000)
## General relationship between OCS and OCS_sd:

write.csv(pca.matrix, file="pca.matrix_OCD.csv")
#unlink("pca.matrix_OCD.csv.gz")
#R.utils::gzip("pca.matrix_OCD.csv")
library(hexbin)

pdf(file = "Fig_correlation_OCS_predictions_pe_mangroves.pdf", width=9, height=8)
par(oma=c(0,0,0,1), mar=c(0,0,0,2))
hexbinplot(pca.matrix$dSOCS_sd_0_100cm_year2000~pca.matrix$dSOCS_0_100cm_year2000, colramp=colorRampPalette(SAGA_pal[[1]][8:20]), main=paste0("Relationship between predictions and p.e. for OCS (t/ha)"), ylab="Prediction error", asp=1, xlab="Predicted values", type="g", lwd=1, lcex=8, inner=.4, cex.labels=1, xbins=50, colorcut=c(0,0.005,0.01,0.03,0.07,0.15,0.25,0.5,1))
dev.off()

## Rasterize errors to 5km resolution:
pe.sp = pca.matrix[,c("dSOCS_sd_0_100cm_year2000","X","Y")]
coordinates(pe.sp) = ~X+Y
proj4string(pe.sp) = CRS("+proj=longlat +datum=WGS84")
pe.sp5km = vect2rast(pe.sp, cell.size=.5, fname="dSOCS_sd_0_100cm_year2000", fun=mean)
#plot(raster(pe.sp5km))
summary(pe.sp5km@data)
writeGDAL(pe.sp5km, "dSOCS_sd_0_100cm_year2000_50km.tif", type = "Byte", options="COMPRESS=DEFLATE", mvFlag=0)

## SOC vs Biomass correlation plot:
pfun.lm <- function(x,y, ...){
  panel.hexbinplot(x,y, ...)  
  panel.lmline(x,y,lty=1,lw=2,col="black")
}

soc_bm = read.csv("biomass_soil.csv")
pdf(file = "Fig_correlation_biomass_soil_mangroves.pdf", width=6, height=5.5)
par(oma=c(0,0,0,1), mar=c(0,0,0,2))
hexbinplot(soc_bm$soil.C~soc_bm$biomass.C, colramp=colorRampPalette(SAGA_pal[[1]][8:20]), main="", ylab=expression(paste("Soil organic carbon stock (Mg C ", ha^{-1}, ")")), asp=1, xlab=expression(paste("Aboveground biomass (Mg C ", ha^{-1}, ")")), type="g", lwd=1, lcex=8, inner=.4, cex.labels=1, xbins=50, colorcut=c(0,0.005,0.01,0.03,0.07,0.15,0.25,0.5,1), panel=pfun.lm)
dev.off()