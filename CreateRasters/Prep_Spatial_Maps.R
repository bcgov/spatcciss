library(climr)
library(data.table)
library(terra)
library(ranger)

addVars <- function(dat) {
  dat[, PPT_MJ := PPT_05 + PPT_06]
  dat[, PPT_JAS := PPT_07 + PPT_08 + PPT_09]
  dat[, PPT.dormant := PPT_at + PPT_wt]
  dat[, CMD.def := pmax(0, 500 - PPT.dormant)]
  dat[, CMDMax := CMD_07]   ## TODO: THIS IS NOT NECESSARILY CMD MAX
  dat[, CMD.total := CMD.def + CMD]
  #dat[, DD_delayed := pmax(0, ((DD_0_at + DD_0_wt)*0.0238) - 1.8386)]
}


# library(sf)
# outline <- st_read("../Common_Files/gpr_000b11a_e/gpr_000b11a_e.shp")
# bc_ol <- outline[1,]
# plot(bc_ol)
# bc_ol <- bc_ol[,"PRUID"]
# bc_ol2 <- vect(bc_ol)
# dem_hr <- rast("../Common_Files/WNA_DEM_SRT_30m_cropped.tif")
# temp <- crop(dem_hr,bc_ol2)
# temp_dem <- aggregate(temp, fact = 5)
# bc_rast <- rasterize(bc_ol, temp_dem)
# final_dem <- mask(temp_dem, bc_rast)
# writeRaster(final_dem, "BC_DEM_100m.tif")
# 
# bc_ol <- disagg(bc_ol, fact = 10)
# t2 <- resample(temp, bc_ol)
# 
setwd("~/FFEC/CCISS_ShinyApp/")
final_dem <- rast("BC_DEM_100m.tif")
final_dem <- aggregate(final_dem, fact = 2)
#################climr####################
points_dat <- as.data.frame(final_dem, cells=T, xy=T)
colnames(points_dat) <- c("id", "lon", "lat", "elev")
points_dat <- points_dat[,c(2,3,4,1)] #restructure for climr input

vars_needed <- c("CMD_sm", "DDsub0_sp", "DD5_sp", "Eref_sm", "Eref_sp", "EXT", 
  "MWMT", "NFFD_sm", "NFFD_sp", "PAS", "PAS_sp", "SHM", "Tave_sm", 
  "Tave_sp", "Tmax_sm", "Tmax_sp", "Tmin", "Tmin_at", "Tmin_sm", 
  "Tmin_sp", "Tmin_wt","CMI", "PPT_05","PPT_06","PPT_07","PPT_08","PPT_09","PPT_at","PPT_wt","CMD_07","CMD"
)
gcms_use <- c("ACCESS-ESM1-5","EC-Earth3","GISS-E2-1-G","MIROC6","MPI-ESM1-2-HR","MRI-ESM2-0")
ssp_use <- "ssp245"
periods_use <- list_gcm_periods()

splits <- c(seq(1,nrow(points_dat), by = 2000000),nrow(points_dat)+1)
BGCmodel <- readRDS("WNA_BGCv12_10May24.rds")
cols <- fread("./WNAv12_3_SubzoneCols.csv")

gcm_curr <- gcms_use[2]
for (gcm_curr in gcms_use[-c(1:3)]){
  cat(gcm_curr, "\n")
  pred_ls <- list()
  for (i in 1:(length(splits) - 1)){
    cat(i, "\n")
    clim_dat <- downscale(points_dat[splits[i]:(splits[i+1]-1),], 
                          gcms = gcm_curr,
                          gcm_periods = periods_use,
                          ssps = ssp_use,
                          max_run = 0L,
                          vars = vars_needed,
                          nthread = 10,
                          return_refperiod = FALSE)
    addVars(clim_dat)
    clim_dat <- na.omit(clim_dat)
    setnames(clim_dat, old = "DDsub0_sp", new = "DD_0_sp")
    temp <- predict(BGCmodel, data = clim_dat, num.threads = 12)
    dat <- data.table(cellnum = clim_dat$id, gcm = clim_dat$GCM, period = clim_dat$PERIOD, bgc_pred = temp$predictions)
    pred_ls[[i]] <- dat
    rm(clim_dat)
    gc()
  }

  all_pred <- rbindlist(pred_ls)
  cat("done predict \n")
  all_pred <-fread("ECEARTH_Save.csv")
  all_pred[,bgc_id := as.numeric(as.factor(bgc_pred))]
  for(curr_per in list_gcm_periods()){
    cat(".")
    dat <- all_pred[period == curr_per,]
    dat[,bgc_id := as.numeric(as.factor(bgc_pred))]

    values(final_dem) <- NA
    final_dem[dat$cellnum] <- dat$bgc_id
    #writeRaster(final_dem, "BGC_Pred_200m.tif")
    bgc_id <- unique(dat[,.(bgc_pred,bgc_id)])
    # fwrite(bgc_id, "BGC_ID.csv")

    bgc_id[cols, colour := i.colour, on = c(bgc_pred = "classification")]

    coltab(final_dem) <- bgc_id[,.(bgc_id,colour)]
    plot(final_dem)
    rgbbgc <- colorize(final_dem, to = "rgb")
    writeRaster(rgbbgc, paste0("./rgb_rasters/bgc_",gcm_curr,"_",curr_per,".tif"), overwrite=TRUE)  
  }

}

# fwrite(all_pred,"GISS_Save.csv")
# all_pred <- fread("ACCESS_Save.csv")

# temp <- BGCmodel$forest$independent.variable.names
# temp[!temp %in% names(clim_dat)]
# b
