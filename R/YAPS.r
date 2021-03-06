#########################################################################
## All functions on this file are modified from the origional
## YAPS github repo: https://github.com/baktoft/yaps_sciRep.git on the date:
## 2018-02-01.  These functions are licensed under the GNU Affero General
## Public License V.3
##########################################################################

#' YAPS: Pelagic fish
#'
#' @param toa $i \times h$ matrix or data.frame holding time-or-arrival data where $h$ is the number of hydrophones and $i$ is the number of pings.
#' @param hydrophone.pos A h x 3 matrix where columns are x, y, and z positions of hydrophones 1 thru h.
#' @param c The approximate speed of sound in water.
#'
#' @return A table of estimated positions in 3D.
#' @export
yaps.pelagic <- function(toa, hydrophone.pos, c = 1500, max.iterations = 10000,
                         params = NULL, verbose = F){
  require(zoo)
  require(TMB)



  ## Remove NAs
  toa.clean <- toa
  toa.clean[is.na(toa)] <- -9999

  data <- list(
    H = as.matrix(hydrophone.pos),
    toa = as.matrix(toa.clean),
    nh = nrow(hydrophone.pos),
    np = nrow(toa),
    c = c
  )

  ## Interlop mising times
  top.interp <- spline(x = 1:data$np, y = toa[,4], xout = 1:data$np)[[2]]

  ###########################
  ## calc start positions
  ###########################
  message('Using spherical interpolation to predict starting times...')
  start.xyz <- TOA.localization(toa = toa,
                                hydrohpone.positions = hydrophone.pos,
                                c = c)
  if(dim(hydrophone.pos)[1] == 4 ){
    ## If 4 hydrophones, select best equation
    eq.neg <- apply(subset(start.xyz, subset = eq == '-')[2:4], MARGIN = 2, FUN = 'diff')
    eq.neg <- sum(abs(eq.neg),na.rm = T)
    eq.pos <- apply(subset(start.xyz, subset = eq == '+')[2:4], MARGIN = 2, FUN = 'diff')
    eq.pos <- sum(abs(eq.pos),na.rm = T)
    ## Pick solutions with smallest travel distance
    if(eq.neg < eq.pos){
      start.xyz <- subset(start.xyz, subset = eq == '-')[2:4]
    }else{
      start.xyz <- subset(start.xyz, subset = eq == '+')[2:4]
      }
  }else{ # 4 or more hydrophones
    start.xyz <- start.xyz[2:4]
  }

  ## Interpolate missing points
  message('Interpolating NA positions from spherical interpolation')
  idx.na <-is.na(start.xyz[,1])
  x <- (1:dim(start.xyz)[1])
  start.xyz[,1] <- approx(x = x[which(!idx.na)],
         y = start.xyz[which(!idx.na),1],xout = x,
         method = 'constant', rule = 2)$y

  idx.na <-is.na(start.xyz[,2])
  x <- (1:dim(start.xyz)[1])
  start.xyz[,2] <- approx(x = x[which(!idx.na)],
         y = start.xyz[which(!idx.na),2],
         xout = x, rule = 2)$y

  idx.x.na <-is.na(start.xyz[,3])
  x <- (1:dim(start.xyz)[1])
  start.xyz[,3] <- approx(x = x[which(!idx.x.na)],
         y = start.xyz[which(!idx.x.na),3],
         xout = x, rule = 2)$y

  names(start.xyz) <- NULL
  if (length(params) != 6){
    message('Using default start parameters')
    params <- list(
      XYZ = as.matrix(start.xyz),
      top = top.interp,	# Estimated random times of pings
      dl = matrix(data = rnorm(n = data$np*data$nh, mean = 0,sd = -10),
                  nrow = data$np,
                  ncol = data$nh),		# latency error
      #c  = c, # Speed of sound
      logSigma_bi = -7.4, #log transformed SD of pulse intervals
      # logSigma_dl = rep(-10,length = data$nh),		# Sigma for latency error
      logSigma_dl = -10,		# Sigma for latency error
      logSigma_toa = -15, # Time of arrival SD
      logSigma_x = -3.5,
      logSigma_y = -3.5,
      logSigma_z = -3.5)
  }else{
    message('Using user specified start parameters')
    params <- append(
      list(XYZ = as.matrix(start.xyz),
           top = top.interp,	# Estimated random times of pings
           dl = matrix(data = rnorm(n = data$np*data$nh, mean = 0,
                                    sd = exp(params$logSigma_dl)),
                       nrow = data$np,
                       ncol = data$nh)#,		# latency error)
         #  c = c
           ),
      params)} # User specificed start parameters


  message('Running YAPS...')
  # Make optimization function
  obj <- MakeADFun(data = data,
                   parameters = params,
                   random = c('XYZ', 'top', 'dl'),
                   DLL="yaps3D_Pelagic", # Position, speed of sound, time of pings
                   inner.control = list(maxit = max.iterations),
                   silent=!verbose, checkParameterOrder = T)
  # Run model
  ## use iterative methods to find optimal parameters
  opt <- nlminb(start = unlist(params[4:length(params)]),
                objective = obj$fn,
                gradient = obj$gr)

  # Extract results
  obj$fn()
  pl <- obj$env$parList()
  jointrep <- sdreport(obj, getJointPrecision=TRUE)
  param_names <- rownames(summary(jointrep))
  sds <- summary(jointrep)[,2]
  summ <- data.frame(param=param_names, sd=sds)
  plsd <- split(summ[,2], f=summ$param)


  return(pl)
}
